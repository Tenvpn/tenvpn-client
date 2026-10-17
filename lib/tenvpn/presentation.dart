import 'awg_source.dart';
import 'configgen/constants.dart';
import 'configgen/subscription.dart';

enum ConnectionPhase { off, connecting, on, error }

/// A short «Подключаемся» reads as a fast VPN; the real IP check carries on
/// behind «Включено» and only its failure turns the button red.
const connectingAnimation = Duration(milliseconds: 500);

ConnectionPhase connectionPhase({
  required bool isStart,
  required bool checkingIp,
  required bool hasIp,
  bool justStarted = false,
}) {
  if (!isStart) return ConnectionPhase.off;
  // The IP on hand right after the tap was measured without the tunnel.
  if (justStarted) return ConnectionPhase.connecting;
  if (hasIp) return ConnectionPhase.on;
  return checkingIp ? ConnectionPhase.on : ConnectionPhase.error;
}

enum ServerTag { mobile, youtube, gemini, reserve }

enum ServerSectionKind { main, mobile, reserve }

class ServerPresentation {
  final String name;
  final String flag;
  final String title;
  final String protocol;
  final Set<ServerTag> tags;
  final ServerSectionKind section;

  const ServerPresentation({
    required this.name,
    required this.flag,
    required this.title,
    required this.protocol,
    required this.tags,
    required this.section,
  });
}

class ServerSection {
  final ServerSectionKind kind;
  final List<ServerPresentation> servers;

  const ServerSection(this.kind, this.servers);
}

final _flagPattern = RegExp(
  r'^\s*((?:[\u{1F1E6}-\u{1F1FF}]{2}))',
  unicode: true,
);
final _emojiPattern = RegExp(
  r'[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{FE0F}\u{200D}]',
  unicode: true,
);
final _bracketPattern = RegExp(r'\(([^)]*)\)');
final _mobileTitle = RegExp(
  r'(серверы\s+)?(для\s+)?обход[а-яё]*\s+бел[а-яё]*\s+спис[а-яё]*',
  caseSensitive: false,
);
final _spaces = RegExp(r'\s+');

const _protocolWords = {
  'hysteria2',
  'hysteria',
  'reality',
  'grpc',
  'ws',
  'xhttp',
};

String protocolLabel(String type, String? network) {
  switch (type.toLowerCase()) {
    case 'wireguard':
      return 'AmneziaWG';
    case 'hysteria2':
      return 'Hysteria2';
    case 'vless':
    case 'vmess':
    case 'trojan':
      return switch (network) {
        'ws' => 'WebSocket',
        'grpc' => 'gRPC',
        'xhttp' => 'XHTTP',
        'h2' || 'http' => 'HTTP/2',
        _ => type.toUpperCase(),
      };
    default:
      return type;
  }
}

ServerPresentation presentServer({
  required String name,
  required String type,
  String? network,
  String? section,
}) {
  final flagMatch = _flagPattern.firstMatch(name);
  final flag = flagMatch?.group(1) ?? '';
  var title = flagMatch == null ? name : name.substring(flagMatch.end);
  final tags = <ServerTag>{};
  final upper = name.toUpperCase();
  if (upper.contains('GEMINI')) tags.add(ServerTag.gemini);
  if (upper.contains('YOUTUBE')) tags.add(ServerTag.youtube);
  final isMobile =
      whitelistWords.hasMatch(name) ||
      (section != null && whitelistWords.hasMatch(section));
  final isReserve =
      type.toLowerCase() == 'wireguard' || section == awgSectionTitle;
  if (isMobile) tags.add(ServerTag.mobile);
  if (isReserve) tags.add(ServerTag.reserve);
  title = title.replaceAllMapped(_bracketPattern, (match) {
    final inner = match.group(1)!.toLowerCase();
    final words = inner
        .split(RegExp(r'[^a-zа-я0-9]+', caseSensitive: false))
        .where((word) => word.isNotEmpty);
    final decorative = words.every(
      (word) =>
          _protocolWords.contains(word) ||
          word == 'gemini' ||
          word == 'youtube',
    );
    return decorative ? '' : match.group(0)!;
  });
  title = title
      .replaceAll(_emojiPattern, '')
      .replaceAllMapped(_mobileTitle, (_) => 'Белые списки')
      .replaceAll(_spaces, ' ')
      .trim();
  if (title.isEmpty) title = name.trim();
  if (isReserve && title == awgSectionTitle) title = 'Запасной';
  return ServerPresentation(
    name: name,
    flag: flag,
    title: title,
    protocol: protocolLabel(type, network),
    tags: tags,
    section: isReserve
        ? ServerSectionKind.reserve
        : isMobile
        ? ServerSectionKind.mobile
        : ServerSectionKind.main,
  );
}

/// Servers missing from configgen's [entries] are classified by name alone.
List<ServerSection> groupServers(
  List<({String name, String type})> proxies,
  List<ServerEntry> entries,
) {
  final byName = {for (final entry in entries) entry.name: entry};
  final buckets = {
    for (final kind in ServerSectionKind.values) kind: <ServerPresentation>[],
  };
  for (final proxy in proxies) {
    final entry = byName[proxy.name];
    final server = presentServer(
      name: proxy.name,
      type: entry?.type ?? proxy.type,
      network: entry?.network,
      section: entry?.section,
    );
    buckets[server.section]!.add(server);
  }
  return [
    for (final kind in ServerSectionKind.values)
      if (buckets[kind]!.isNotEmpty) ServerSection(kind, buckets[kind]!),
  ];
}

String flagEmoji(String countryCode) {
  final code = countryCode.trim().toUpperCase();
  if (!RegExp(r'^[A-Z]{2}$').hasMatch(code)) return '';
  return String.fromCharCodes(code.codeUnits.map((unit) => unit + 0x1F1A5));
}

const _countryNames = {
  'NL': ('Нидерланды', 'Netherlands'),
  'DE': ('Германия', 'Germany'),
  'SE': ('Швеция', 'Sweden'),
  'RO': ('Румыния', 'Romania'),
  'US': ('США', 'United States'),
  'FI': ('Финляндия', 'Finland'),
  'FR': ('Франция', 'France'),
  'GB': ('Великобритания', 'United Kingdom'),
  'PL': ('Польша', 'Poland'),
  'LV': ('Латвия', 'Latvia'),
  'LT': ('Литва', 'Lithuania'),
  'EE': ('Эстония', 'Estonia'),
  'KZ': ('Казахстан', 'Kazakhstan'),
  'TR': ('Турция', 'Turkey'),
  'AM': ('Армения', 'Armenia'),
  'GE': ('Грузия', 'Georgia'),
  'RS': ('Сербия', 'Serbia'),
  'CH': ('Швейцария', 'Switzerland'),
  'AT': ('Австрия', 'Austria'),
  'CZ': ('Чехия', 'Czechia'),
  'ES': ('Испания', 'Spain'),
  'IT': ('Италия', 'Italy'),
  'JP': ('Япония', 'Japan'),
  'SG': ('Сингапур', 'Singapore'),
  'HK': ('Гонконг', 'Hong Kong'),
  'CA': ('Канада', 'Canada'),
  'AE': ('ОАЭ', 'UAE'),
  'RU': ('Россия', 'Russia'),
  'VN': ('Вьетнам', 'Vietnam'),
};

String countryName(String countryCode, {required bool russian}) {
  final code = countryCode.trim().toUpperCase();
  final names = _countryNames[code];
  if (names == null) return code;
  return russian ? names.$1 : names.$2;
}

/// `expire` of subscription-userinfo, in seconds; zero means not sent.
DateTime? expiryFromHeader(int expire) {
  if (expire <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(expire * 1000);
}

int daysLeft(DateTime expiry, DateTime now) {
  final end = DateTime(expiry.year, expiry.month, expiry.day);
  final today = DateTime(now.year, now.month, now.day);
  return end.difference(today).inDays;
}

typedef ImportLink = ({String url, AwgSource? awg, String? token});

/// A bare https link, the bot's `tenvpn://import?sub=&token=` or the older
/// `tenvpn://install-config?url=&awg=&awg_token=`.
ImportLink? parseImportLink(String input) {
  var text = input.trim();
  while (text.endsWith('.') || text.endsWith(',')) {
    text = text.substring(0, text.length - 1);
  }
  final uri = Uri.tryParse(text);
  if (uri == null) return null;
  if (uri.scheme == 'tenvpn' && uri.host == 'import') {
    final sub = uri.queryParameters['sub'];
    final nested = sub == null ? null : parseImportLink(sub);
    if (nested == null || nested.token != null) return null;
    final token = uri.queryParameters['token']?.trim();
    return (
      url: nested.url,
      awg: null,
      token: token == null || token.isEmpty ? null : token,
    );
  }
  if (uri.scheme == 'tenvpn' || uri.scheme == 'clash') {
    final inner = uri.queryParameters['url'];
    final nested = inner == null ? null : parseImportLink(inner);
    if (nested == null) return null;
    final awgUrl = uri.queryParameters['awg'];
    final awgToken = uri.queryParameters['awg_token'];
    final awg = awgUrl != null && awgToken != null && awgToken.isNotEmpty
        ? AwgSource(url: awgUrl, token: awgToken)
        : null;
    return (url: nested.url, awg: awg, token: null);
  }
  if ((uri.scheme == 'https' || uri.scheme == 'http') && uri.host.isNotEmpty) {
    return (url: text, awg: null, token: null);
  }
  return null;
}

/// Fastest first, then not measured yet, then not answering.
List<ServerPresentation> sortByPing(
  List<ServerPresentation> servers,
  int? Function(String name) delayOf,
) {
  int rank(ServerPresentation s) {
    final delay = delayOf(s.name);
    if (delay == null || delay == 0) return 1 << 30;
    if (delay < 0) return 1 << 31;
    return delay;
  }

  final indexed = servers.indexed.toList()
    ..sort((a, b) {
      final byPing = rank(a.$2).compareTo(rank(b.$2));
      return byPing != 0 ? byPing : a.$1.compareTo(b.$1);
    });
  return [for (final (_, server) in indexed) server];
}
