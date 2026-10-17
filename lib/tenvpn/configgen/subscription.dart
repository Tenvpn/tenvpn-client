import 'dart:convert';

import 'package:yaml/yaml.dart';

import 'constants.dart';
import 'errors.dart';

class ServerEntry {
  final String name;
  final String type;
  final String? network;
  final String? section;

  const ServerEntry({
    required this.name,
    required this.type,
    this.network,
    this.section,
  });

  String get transport => network ?? type;
}

class ParsedSubscription {
  final List<Map<String, dynamic>> proxies;
  final List<ServerEntry> servers;
  final List<String> separators;

  const ParsedSubscription({
    required this.proxies,
    required this.servers,
    required this.separators,
  });
}

final _shareLinkPattern = RegExp(
  r'^(vless|vmess|trojan|ss|ssr|hysteria2?|hy2|tuic|wireguard|socks5?|https?|anytls)://',
  caseSensitive: false,
  multiLine: true,
);
final _ipv4Pattern = RegExp(r'^\d{1,3}(\.\d{1,3}){3}$');
final _hostnamePattern = RegExp(
  r'^(?=.{1,253}$)([a-z0-9_]([a-z0-9_-]{0,61}[a-z0-9])?\.)+[a-z][a-z0-9-]*[a-z0-9]$',
  caseSensitive: false,
);
final _decorationPattern = RegExp(
  r'[\u{1F000}-\u{1FFFF}\u{2190}-\u{21FF}\u{2600}-\u{27BF}\u{FE0F}]',
  unicode: true,
);

ParsedSubscription parseSubscription(String text) {
  final content = text.startsWith('﻿') ? text.substring(1) : text;
  final trimmed = content.trim();
  if (trimmed.isEmpty) {
    throw const ConfigGenException(ConfigGenErrorCode.empty);
  }
  final lower = trimmed
      .substring(0, trimmed.length.clamp(0, 512))
      .toLowerCase();
  if (lower.startsWith('<!doctype') || lower.startsWith('<html')) {
    throw const ConfigGenException(ConfigGenErrorCode.html);
  }
  if (_looksLikeShareLinks(trimmed)) {
    throw const ConfigGenException(ConfigGenErrorCode.shareLinks);
  }
  final Object? document;
  try {
    document = loadYaml(content);
  } on YamlException catch (e) {
    throw ConfigGenException(ConfigGenErrorCode.invalidYaml, e.message);
  }
  if (document is! YamlMap) {
    throw const ConfigGenException(ConfigGenErrorCode.notAConfig);
  }
  final rawProxies = document['proxies'];
  if (rawProxies is! YamlList) {
    throw const ConfigGenException(ConfigGenErrorCode.noProxies);
  }
  final proxies = <Map<String, dynamic>>[];
  final servers = <ServerEntry>[];
  final separators = <String>[];
  final usedNames = <String>{};
  String? section;
  for (final item in rawProxies) {
    if (item is! YamlMap) continue;
    final proxy = toPlain(item) as Map<String, dynamic>;
    final name = proxy['name'];
    final type = proxy['type'];
    if (name is! String || name.trim().isEmpty || type is! String) continue;
    if (!isRoutableHost(proxy['server'])) {
      separators.add(name);
      section = sectionTitle(name);
      continue;
    }
    final unique = uniqueName(name, usedNames, reserved: reservedProxyNames);
    usedNames.add(unique);
    proxy['name'] = unique;
    proxies.add(proxy);
    final network = proxy['network'];
    servers.add(
      ServerEntry(
        name: unique,
        type: type,
        network: network is String && network != 'tcp' ? network : null,
        section: section,
      ),
    );
  }
  if (proxies.isEmpty) {
    throw const ConfigGenException(ConfigGenErrorCode.noProxies);
  }
  return ParsedSubscription(
    proxies: proxies,
    servers: servers,
    separators: separators,
  );
}

bool _looksLikeShareLinks(String text) {
  if (_shareLinkPattern.hasMatch(text)) return true;
  if (text.contains(':') || text.contains('\n') && text.contains(' ')) {
    return false;
  }
  try {
    final decoded = utf8.decode(
      base64.decode(base64.normalize(text.replaceAll(RegExp(r'\s'), ''))),
      allowMalformed: true,
    );
    return _shareLinkPattern.hasMatch(decoded);
  } on FormatException {
    return false;
  }
}

bool isRoutableHost(Object? server) {
  if (server is! String || server.isEmpty) return false;
  final host = server.trim();
  if (host.contains(':')) return true;
  if (_ipv4Pattern.hasMatch(host)) {
    final octets = host.split('.').map(int.parse).toList();
    if (octets.any((o) => o > 255)) return false;
    return octets.first != 0 && octets.first != 127;
  }
  return _hostnamePattern.hasMatch(host);
}

String sectionTitle(String separatorName) {
  return separatorName
      .replaceAll(_decorationPattern, '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String uniqueName(
  String name,
  Set<String> used, {
  Set<String> reserved = const {},
}) {
  bool taken(String candidate) =>
      used.contains(candidate) || reserved.contains(candidate);
  if (!taken(name)) return name;
  var index = 2;
  while (taken('$name ($index)')) {
    index++;
  }
  return '$name ($index)';
}

Object? toPlain(Object? node) {
  if (node is YamlMap) {
    return <String, dynamic>{
      for (final entry in node.entries)
        entry.key.toString(): toPlain(entry.value),
    };
  }
  if (node is YamlList) {
    return node.map(toPlain).toList();
  }
  if (node is Map) {
    return <String, dynamic>{
      for (final entry in node.entries)
        entry.key.toString(): toPlain(entry.value),
    };
  }
  if (node is List) {
    return node.map(toPlain).toList();
  }
  return node;
}
