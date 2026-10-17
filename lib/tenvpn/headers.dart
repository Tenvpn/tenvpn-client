import 'dart:convert';

const _minUpdateInterval = Duration(hours: 1);
const _maxUpdateInterval = Duration(hours: 24);

String? parseProfileTitle(String? header) {
  if (header == null || header.trim().isEmpty) return null;
  final value = header.trim();
  if (!value.startsWith('base64:')) return value;
  try {
    final decoded = utf8.decode(base64.decode(value.substring(7))).trim();
    return decoded.isEmpty ? null : decoded;
  } on FormatException {
    return null;
  }
}

Duration? parseUpdateInterval(String? header) {
  final hours = int.tryParse(header?.trim() ?? '');
  if (hours == null || hours <= 0) return null;
  final interval = Duration(hours: hours);
  if (interval < _minUpdateInterval) return _minUpdateInterval;
  if (interval > _maxUpdateInterval) return _maxUpdateInterval;
  return interval;
}
