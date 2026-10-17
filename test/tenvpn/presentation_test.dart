import 'package:fl_clash/tenvpn/tenvpn.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('connectionPhase', () {
    test('is off whenever the tunnel is not started', () {
      expect(
        connectionPhase(isStart: false, checkingIp: true, hasIp: true),
        ConnectionPhase.off,
      );
    });

    test('connects for a moment, then reads as on while the check runs', () {
      expect(
        connectionPhase(
          isStart: true,
          checkingIp: true,
          hasIp: false,
          justStarted: true,
        ),
        ConnectionPhase.connecting,
      );
      expect(
        connectionPhase(isStart: true, checkingIp: true, hasIp: false),
        ConnectionPhase.on,
      );
      expect(
        connectionPhase(
          isStart: true,
          checkingIp: false,
          hasIp: true,
          justStarted: true,
        ),
        ConnectionPhase.connecting,
      );
      expect(
        connectionPhase(isStart: true, checkingIp: false, hasIp: true),
        ConnectionPhase.on,
      );
    });

    test('is an error when the check gave up without an IP', () {
      expect(
        connectionPhase(isStart: true, checkingIp: false, hasIp: false),
        ConnectionPhase.error,
      );
    });
  });

  group('presentServer', () {
    test('splits the flag and drops decorative emoji', () {
      final server = presentServer(
        name: '🇸🇪 ⚡ Швеция',
        type: 'vless',
        network: 'ws',
      );
      expect(server.flag, '🇸🇪');
      expect(server.title, 'Швеция');
      expect(server.protocol, 'WebSocket');
      expect(server.section, ServerSectionKind.main);
      expect(server.tags, isEmpty);
    });

    test('moves protocol and purpose out of the brackets into labels', () {
      final hysteria = presentServer(
        name: '🇳🇱 ⚡ Нидерланды (Hysteria2) 🚀',
        type: 'hysteria2',
      );
      expect(hysteria.title, 'Нидерланды');
      expect(hysteria.protocol, 'Hysteria2');

      final gemini = presentServer(
        name: '🇺🇸 США (GEMINI + ) 🤖',
        type: 'vless',
      );
      expect(gemini.title, 'США');
      expect(gemini.tags, {ServerTag.gemini});
      expect(gemini.protocol, 'VLESS');
    });

    test('keeps brackets that carry real meaning', () {
      final server = presentServer(name: '🇩🇪 Германия (2)', type: 'vless');
      expect(server.title, 'Германия (2)');
    });

    test('names the whitelist servers neutrally', () {
      final server = presentServer(
        name: '🇪🇺  Обход белых списков 1',
        type: 'vless',
        network: 'xhttp',
        section: 'Серверы для обхода белых списков',
      );
      expect(server.title, 'Белые списки 1');
      expect(server.protocol, 'XHTTP');
      expect(server.section, ServerSectionKind.mobile);
      expect(server.tags, {ServerTag.mobile});
    });

    test('recognises the mobile section by the server name alone', () {
      final server = presentServer(
        name: 'Обход белых списков 3',
        type: 'vless',
      );
      expect(server.section, ServerSectionKind.mobile);
      expect(server.flag, isEmpty);
    });

    test('puts AmneziaWG into the backup section', () {
      final server = presentServer(name: awgDefaultName, type: 'wireguard');
      expect(server.section, ServerSectionKind.reserve);
      expect(server.title, 'Запасной');
      expect(server.protocol, 'AmneziaWG');
      expect(server.tags, {ServerTag.reserve});
    });

    test('tags YouTube servers and falls back to the raw name', () {
      expect(presentServer(name: 'YouTube 🚀', type: 'trojan').tags, {
        ServerTag.youtube,
      });
      expect(presentServer(name: '🚀', type: 'vless').title, '🚀');
    });
  });

  test('protocolLabel covers the transports from the subscription', () {
    expect(protocolLabel('vless', 'grpc'), 'gRPC');
    expect(protocolLabel('vmess', 'h2'), 'HTTP/2');
    expect(protocolLabel('vless', null), 'VLESS');
    expect(protocolLabel('ss', null), 'ss');
  });

  test('groupServers orders sections and classifies unknown servers', () {
    final sections = groupServers(
      [
        (name: awgDefaultName, type: 'WireGuard'),
        (name: '🇪🇺 Обход белых списков 1', type: 'Vless'),
        (name: '🇸🇪 Швеция', type: 'Vless'),
        (name: '🇳🇱 Нидерланды', type: 'Vless'),
      ],
      const [
        ServerEntry(
          name: '🇪🇺 Обход белых списков 1',
          type: 'vless',
          network: 'xhttp',
          section: 'Серверы для обхода белых списков',
        ),
        ServerEntry(name: '🇸🇪 Швеция', type: 'vless', network: 'ws'),
      ],
    );
    expect(sections.map((section) => section.kind), [
      ServerSectionKind.main,
      ServerSectionKind.mobile,
      ServerSectionKind.reserve,
    ]);
    expect(sections.first.servers.map((server) => server.title), [
      'Швеция',
      'Нидерланды',
    ]);
    expect(sections.first.servers.first.protocol, 'WebSocket');
    expect(sections[1].servers.single.protocol, 'XHTTP');
    expect(sections.last.servers.single.protocol, 'AmneziaWG');
  });

  test('flagEmoji and countryName', () {
    expect(flagEmoji('nl'), '🇳🇱');
    expect(flagEmoji('NLD'), '');
    expect(countryName('NL', russian: true), 'Нидерланды');
    expect(countryName('de', russian: false), 'Germany');
    expect(countryName('ZZ', russian: true), 'ZZ');
  });

  test('expiry helpers', () {
    expect(expiryFromHeader(0), isNull);
    final expiry = expiryFromHeader(1795000000)!;
    expect(expiry.millisecondsSinceEpoch, 1795000000 * 1000);
    expect(daysLeft(DateTime(2026, 11, 12, 1), DateTime(2026, 11, 10, 23)), 2);
    expect(daysLeft(DateTime(2026, 11, 9), DateTime(2026, 11, 10)), -1);
  });

  group('parseImportLink', () {
    test('accepts a bare link with stray spaces and punctuation', () {
      final link = parseImportLink('  https://sub.example.com/abc. ');
      expect(link?.url, 'https://sub.example.com/abc');
      expect(link?.awg, isNull);
    });

    test('unwraps the bot link together with its AmneziaWG source', () {
      final inner = Uri.encodeComponent('https://sub.example.com/abc');
      final awg = Uri.encodeComponent('https://api.example.com/api/app/v1/awg');
      final link = parseImportLink(
        'tenvpn://install-config?url=$inner&awg=$awg&awg_token=t0k',
      );
      expect(link?.url, 'https://sub.example.com/abc');
      expect(link?.awg?.url, 'https://api.example.com/api/app/v1/awg');
      expect(link?.awg?.token, 't0k');
    });

    test('ignores an AmneziaWG source without a token', () {
      final inner = Uri.encodeComponent('https://sub.example.com/abc');
      final link = parseImportLink(
        'tenvpn://install-config?url=$inner&awg=https://a.example.com',
      );
      expect(link?.awg, isNull);
    });

    test('rejects what is not a subscription link', () {
      expect(parseImportLink('привет'), isNull);
      expect(parseImportLink('vless://uuid@host:443'), isNull);
      expect(parseImportLink('tenvpn://install-config'), isNull);
      expect(parseImportLink('tenvpn://install-config?url=nope'), isNull);
      expect(parseImportLink('http://[::1'), isNull);
    });
  });

  test('sortByPing puts the fastest first, unmeasured then dead last', () {
    ServerPresentation s(String name) =>
        presentServer(name: name, type: 'vless');
    final delays = {'a': 120, 'b': -1, 'c': 40, 'd': null, 'e': 0, 'f': 40};
    final sorted = sortByPing([
      s('a'),
      s('b'),
      s('c'),
      s('d'),
      s('e'),
      s('f'),
    ], (name) => delays[name]);
    expect(sorted.map((server) => server.name), ['c', 'f', 'a', 'd', 'e', 'b']);
  });
}
