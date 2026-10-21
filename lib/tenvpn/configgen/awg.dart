import 'constants.dart';
import 'errors.dart';

final _wireguardKeyPattern = RegExp(r'^[A-Za-z0-9+/]{42}[AEIMQUYcgkosw048]=$');
final _headerPattern = RegExp(r'^\d+(-\d+)?$');

const _intOptions = ['jc', 'jmin', 'jmax', 's1', 's2', 's3', 's4', 'itime'];
const _headerOptions = ['h1', 'h2', 'h3', 'h4'];
const _stringOptions = ['i1', 'i2', 'i3', 'i4', 'i5', 'j1', 'j2', 'j3'];

// mihomo applies AmneziaWG 3.x fields only with `version: 3`, which rejects the 1.5-only ones.
const _v3RangeOptions = {
  'contentpaddingaddition': 'content-padding-addition',
  'rekeyaftertime': 'rekey-after-time',
  'rekeytimeout': 'rekey-timeout',
  'rejectaftertime': 'reject-after-time',
  'keepalivetimeout': 'keepalive-timeout',
  'maxhandshakeattempts': 'max-handshake-attempts',
};
const _v3BoolOptions = {
  'randomtrailers': 'random-trailers',
  'disablecookies': 'disable-cookies',
};
const _v15OnlyOptions = ['j1', 'j2', 'j3', 'itime'];
final _base64KeyPattern = RegExp(r'^[A-Za-z0-9+/]{43}=$');

/// Turns a wg-quick `.conf` (the file vpnbot renders for AmneziaVPN) into a
/// mihomo `wireguard` proxy with `amnezia-wg-option`.
Map<String, dynamic> parseAwgConf(String conf, {String name = awgDefaultName}) {
  final sections = _parseIni(conf);
  final interface = sections['interface'];
  final peer = sections['peer'];
  if (interface == null || peer == null) {
    throw const ConfigGenException(
      ConfigGenErrorCode.awgInvalid,
      'need [Interface] and [Peer]',
    );
  }
  final privateKey = _requireKey(interface, 'privatekey');
  final publicKey = _requireKey(peer, 'publickey');
  final endpoint = _parseEndpoint(peer['endpoint']);
  final addresses = _splitList(interface['address']);
  final ipv4 = addresses.where((a) => !a.contains(':')).firstOrNull;
  final ipv6 = addresses.where((a) => a.contains(':')).firstOrNull;
  if (ipv4 == null && ipv6 == null) {
    throw const ConfigGenException(
      ConfigGenErrorCode.awgInvalid,
      'Address is missing',
    );
  }
  final proxy = <String, dynamic>{
    'name': name,
    'type': 'wireguard',
    'server': endpoint.host,
    'port': endpoint.port,
    if (ipv4 != null) 'ip': _stripPrefix(ipv4),
    if (ipv6 != null) 'ipv6': _stripPrefix(ipv6),
    'private-key': privateKey,
    'public-key': publicKey,
  };
  final presharedKey = peer['presharedkey'];
  if (presharedKey != null && presharedKey.isNotEmpty) {
    proxy['pre-shared-key'] = _checkKey(presharedKey, 'PresharedKey');
  }
  final allowedIps = _splitList(peer['allowedips']);
  proxy['allowed-ips'] = allowedIps.isEmpty
      ? ['0.0.0.0/0', '::/0']
      : allowedIps;
  proxy['udp'] = true;
  final mtu = _optionalInt(interface, 'mtu');
  if (mtu != null) proxy['mtu'] = mtu;
  final keepalive = _optionalInt(peer, 'persistentkeepalive');
  if (keepalive != null && keepalive > 0) {
    proxy['persistent-keepalive'] = keepalive;
  }
  final dns = _splitList(interface['dns']);
  if (dns.isNotEmpty) {
    proxy['remote-dns-resolve'] = true;
    proxy['dns'] = dns;
  }
  final amnezia = _amneziaOptions(interface);
  if (amnezia.isNotEmpty) proxy['amnezia-wg-option'] = amnezia;
  return proxy;
}

Map<String, dynamic> _amneziaV3Options(Map<String, String> interface) {
  final options = <String, dynamic>{};
  final headerKey = interface['headerprotectionkey'];
  if (headerKey != null && headerKey.isNotEmpty) {
    if (!_base64KeyPattern.hasMatch(headerKey)) {
      throw const ConfigGenException(
        ConfigGenErrorCode.awgInvalid,
        'HeaderProtectionKey is not a base64 key',
      );
    }
    options['header-protection-key'] = headerKey;
  }
  _v3RangeOptions.forEach((iniKey, yamlKey) {
    final value = interface[iniKey];
    // awg-quick saves an unset padding as `ContentPaddingAddition = 0`.
    if (value == null || value.isEmpty || value == '0') return;
    if (!_headerPattern.hasMatch(value)) {
      throw ConfigGenException(
        ConfigGenErrorCode.awgInvalid,
        '$iniKey must be a number or a range',
      );
    }
    options[yamlKey] = value;
  });
  _v3BoolOptions.forEach((iniKey, yamlKey) {
    final value = interface[iniKey]?.toLowerCase();
    if (value == null || value.isEmpty) return;
    if (const ['on', 'true', '1'].contains(value)) {
      options[yamlKey] = true;
    } else if (!const ['off', 'false', '0'].contains(value)) {
      throw ConfigGenException(
        ConfigGenErrorCode.awgInvalid,
        '$iniKey must be on or off',
      );
    }
  });
  return options;
}

Map<String, Map<String, String>> _parseIni(String conf) {
  final sections = <String, Map<String, String>>{};
  Map<String, String>? current;
  for (final rawLine in conf.split(RegExp(r'\r?\n'))) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) continue;
    if (line.startsWith('[') && line.endsWith(']')) {
      final title = line.substring(1, line.length - 1).trim().toLowerCase();
      current = sections.putIfAbsent(title, () => {});
      continue;
    }
    final separator = line.indexOf('=');
    if (current == null || separator <= 0) continue;
    final key = line.substring(0, separator).trim().toLowerCase();
    final value = line.substring(separator + 1).trim();
    current[key] = current.containsKey(key) ? '${current[key]}, $value' : value;
  }
  return sections;
}

String _requireKey(Map<String, String> section, String key) {
  final value = section[key];
  if (value == null || value.isEmpty) {
    throw ConfigGenException(ConfigGenErrorCode.awgInvalid, '$key is missing');
  }
  return _checkKey(value, key);
}

String _checkKey(String value, String label) {
  if (!_wireguardKeyPattern.hasMatch(value)) {
    throw ConfigGenException(
      ConfigGenErrorCode.awgInvalid,
      '$label is not a base64 WireGuard key',
    );
  }
  return value;
}

({String host, int port}) _parseEndpoint(String? endpoint) {
  final value = endpoint?.trim() ?? '';
  final separator = value.lastIndexOf(':');
  final port = separator > 0
      ? int.tryParse(value.substring(separator + 1))
      : null;
  if (port == null || port <= 0 || port > 65535) {
    throw const ConfigGenException(
      ConfigGenErrorCode.awgInvalid,
      'Endpoint must be host:port',
    );
  }
  var host = value.substring(0, separator);
  if (host.startsWith('[') && host.endsWith(']')) {
    host = host.substring(1, host.length - 1);
  }
  return (host: host, port: port);
}

List<String> _splitList(String? value) {
  if (value == null) return const [];
  return value
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

String _stripPrefix(String address) {
  final slash = address.indexOf('/');
  return slash == -1 ? address : address.substring(0, slash);
}

int? _optionalInt(Map<String, String> section, String key) {
  final value = section[key];
  if (value == null || value.isEmpty) return null;
  final parsed = int.tryParse(value);
  if (parsed == null) {
    throw ConfigGenException(
      ConfigGenErrorCode.awgInvalid,
      '$key is not a number',
    );
  }
  return parsed;
}

Map<String, dynamic> _amneziaOptions(Map<String, String> interface) {
  final options = <String, dynamic>{};
  for (final key in _intOptions) {
    final value = _optionalInt(interface, key);
    if (value != null) options[key] = value;
  }
  for (final key in _headerOptions) {
    final value = interface[key];
    if (value == null || value.isEmpty) continue;
    if (!_headerPattern.hasMatch(value)) {
      throw ConfigGenException(
        ConfigGenErrorCode.awgInvalid,
        '$key must be a number or a range',
      );
    }
    options[key] = value;
  }
  for (final key in _stringOptions) {
    final value = interface[key];
    if (value != null && value.isNotEmpty) options[key] = value;
  }
  final v3 = _amneziaV3Options(interface);
  if (v3.isNotEmpty) {
    for (final key in _v15OnlyOptions) {
      options.remove(key);
    }
    options
      ..addAll(v3)
      ..['version'] = 3;
  }
  final obfuscated = options.entries.any(
    (entry) => entry.value is! int || entry.value != 0,
  );
  return obfuscated ? options : const {};
}
