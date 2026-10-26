import 'presentation.dart';

const tenvpnSupportUrl = 'https://t.me/TenvpnSupp';
const tenvpnCabinetUrl = 'https://cabinet.tenproxy.site';
const tenvpnCabinetSiteUrl = 'https://cabinet.tenproxy.site/site/';
const supportLogLines = 200;

/// The server «Авто» would take in its ordinary tier: the lowest measured
/// ping among the main servers. AmneziaWG stays out of «Авто», so out of here.
String? bestServerName(
  Iterable<ServerPresentation> servers,
  int? Function(String name) delayOf,
) {
  String? best;
  var bestDelay = 1 << 30;
  for (final server in servers) {
    if (server.section != ServerSectionKind.main) continue;
    if (server.tags.contains(ServerTag.reserve)) continue;
    final delay = delayOf(server.name);
    if (delay == null || delay <= 0 || delay >= bestDelay) continue;
    best = server.name;
    bestDelay = delay;
  }
  return best;
}

bool serverMatches(ServerPresentation server, String query) {
  final words = query.toLowerCase().split(RegExp(r'\s+'))
    ..removeWhere((w) => w.isEmpty);
  if (words.isEmpty) return true;
  final code = String.fromCharCodes(
    server.flag.runes.map((rune) => rune - 0x1F1A5),
  );
  final haystack = [
    server.title,
    server.protocol,
    server.name,
    if (code.length == 2) ...[
      countryName(code, russian: false),
      countryName(code, russian: true),
    ],
  ].join(' ').toLowerCase();
  return words.every(haystack.contains);
}

final _scrubbers = <(RegExp, String)>[
  (RegExp(r'[a-z][a-z0-9+.-]*://\S+', caseSensitive: false), '<link>'),
  (
    RegExp(
      r'\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b',
      caseSensitive: false,
    ),
    '<uuid>',
  ),
  (
    RegExp(
      r'\b(token|password|passwd|pass|secret|key|pbk|sid|auth|uuid|id)'
      r'\s*[=:]\s*[^\s&,;]+',
      caseSensitive: false,
    ),
    r'$1=<hidden>',
  ),
  (RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+'), '<email>'),
  (RegExp(r'\b(?:\d{1,3}\.){3}\d{1,3}(?::\d+)?\b'), '<ip>'),
  (
    RegExp(
      r'\[?(?:\b(?:[0-9a-f]{1,4}:){4,7}[0-9a-f]{1,4}\b'
      r'|\b(?:[0-9a-f]{1,4}:){1,6}:(?:[0-9a-f]{1,4}(?::[0-9a-f]{1,4})*)?)'
      r'\]?(?::\d+)?',
      caseSensitive: false,
    ),
    '<ip>',
  ),
  (RegExp(r'[A-Za-z0-9+/_=-]{32,}'), '<hidden>'),
];

/// Everything that would let a stranger use the subscription or find the
/// person goes: links, UUIDs, keys and tokens, e-mails, IP addresses.
String scrubSupportText(String text) {
  var out = text;
  for (final (pattern, replacement) in _scrubbers) {
    out = out.replaceAllMapped(pattern, (m) {
      if (!replacement.contains(r'$1')) return replacement;
      return replacement.replaceFirst(r'$1', m.group(1) ?? '');
    });
  }
  return out;
}

String buildSupportReport({
  required String version,
  required String platform,
  required String os,
  required String network,
  required String server,
  required String look,
  required Iterable<String> logs,
  required DateTime now,
}) {
  final lines = logs.toList();
  final tail = lines.length > supportLogLines
      ? lines.sublist(lines.length - supportLogLines)
      : lines;
  return scrubSupportText(
    [
      'TENVPN $version · $platform · $os',
      'Сеть: $network',
      'Сервер: $server',
      'Вид: $look',
      'Время: ${now.toIso8601String()}',
      '',
      '— журнал (последние ${tail.length}) —',
      ...tail,
    ].join('\n'),
  );
}
