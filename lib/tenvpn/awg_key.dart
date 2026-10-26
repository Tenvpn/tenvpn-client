import 'dart:convert';
import 'dart:io';

enum AwgKeyError { empty, notAwg, unreadable }

final class AwgKeyException implements Exception {
  final AwgKeyError error;

  const AwgKeyException(this.error);
}

/// A pasted AmneziaWG key to wg-quick text: either the `.conf` itself or an
/// AmneziaVPN `vpn://` share — base64url of Qt's qCompress (4-byte length,
/// then zlib) around JSON whose AWG container holds the config.
String decodeAwgKey(String input) {
  final text = input.trim();
  if (text.isEmpty) throw const AwgKeyException(AwgKeyError.empty);
  if (text.contains('[Interface]')) return text;
  if (!text.toLowerCase().startsWith('vpn://')) {
    throw const AwgKeyException(AwgKeyError.notAwg);
  }
  final Object? json;
  try {
    final packed = base64Url.decode(base64Url.normalize(text.substring(6)));
    if (packed.length < 5) throw const FormatException('too short');
    json = jsonDecode(utf8.decode(zlib.decode(packed.sublist(4))));
  } on Object {
    throw const AwgKeyException(AwgKeyError.unreadable);
  }
  final conf = _findConf(json);
  if (conf == null) throw const AwgKeyException(AwgKeyError.notAwg);
  return conf.trim();
}

String? _findConf(Object? node) {
  if (node is String) {
    if (node.trimLeft().startsWith('{')) {
      try {
        return _findConf(jsonDecode(node));
      } on FormatException {
        return null;
      }
    }
    return node.contains('[Interface]') ? node : null;
  }
  if (node is Map) {
    for (final key in ['config', 'last_config', 'awg', 'containers']) {
      final found = _findConf(node[key]);
      if (found != null) return found;
    }
    for (final value in node.values) {
      final found = _findConf(value);
      if (found != null) return found;
    }
  }
  if (node is List) {
    for (final item in node) {
      final found = _findConf(item);
      if (found != null) return found;
    }
  }
  return null;
}
