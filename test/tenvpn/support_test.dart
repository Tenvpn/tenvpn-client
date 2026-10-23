import 'package:fl_clash/tenvpn/tenvpn.dart';
import 'package:flutter_test/flutter_test.dart';

ServerPresentation _server(
  String name, {
  String type = 'vless',
  String? section,
}) => presentServer(name: name, type: type, section: section);

void main() {
  group('best server', () {
    final servers = [
      _server('🇸🇪 Швеция'),
      _server('🇳🇱 Нидерланды'),
      _server('🇩🇪 Германия'),
      _server('🇪🇺 Обход белых списков 1'),
      _server(awgDefaultName, type: 'wireguard'),
    ];

    test('is the lowest ping among ordinary servers', () {
      final delays = {
        '🇸🇪 Швеция': 120,
        '🇳🇱 Нидерланды': 79,
        '🇩🇪 Германия': -1,
        '🇪🇺 Обход белых списков 1': 20,
        awgDefaultName: 10,
      };
      expect(bestServerName(servers, (n) => delays[n]), '🇳🇱 Нидерланды');
    });

    test('is nobody before the first measurement', () {
      expect(bestServerName(servers, (_) => null), isNull);
      expect(bestServerName(servers, (_) => 0), isNull);
      expect(bestServerName(servers, (_) => -1), isNull);
    });
  });

  group('server search', () {
    final sweden = _server('🇸🇪 Швеция', section: null);

    test('finds by country in both languages, protocol and name', () {
      expect(serverMatches(sweden, ''), isTrue);
      expect(serverMatches(sweden, 'шве'), isTrue);
      expect(serverMatches(sweden, 'Sweden'), isTrue);
      expect(serverMatches(sweden, 'vless'), isTrue);
      expect(serverMatches(sweden, 'шве vless'), isTrue);
      expect(serverMatches(sweden, 'герм'), isFalse);
    });
  });

  group('support report', () {
    test('keeps nothing that opens the subscription or finds the person', () {
      const raw =
          'fetch https://sub.example.com/abc?token=xyz failed\n'
          'vless://3f2a1b4c-1111-2222-3333-444455556666@203.0.113.7:443?pbk=AbCd\n'
          'dial 198.51.100.20:8443 and [2001:db8::1]:443\n'
          'uuid: 3f2a1b4c-1111-2222-3333-444455556666 password=hunter2\n'
          'mail me at someone@example.org\n'
          'key ZmFrZWtleWZha2VrZXlmYWtla2V5ZmFrZWtleWZha2U=\n'
          '2026-10-23 12:23:50 timeout to ya.ru';
      final clean = scrubSupportText(raw);
      for (final secret in [
        'sub.example.com',
        'xyz',
        '3f2a1b4c',
        '203.0.113.7',
        '198.51.100.20',
        '2001:db8',
        'hunter2',
        'someone@',
        'ZmFrZWtl',
      ]) {
        expect(clean, isNot(contains(secret)), reason: secret);
      }
      expect(clean, contains('2026-10-23 12:23:50 timeout to ya.ru'));
      expect(clean, contains('<link>'));
      expect(clean, contains('<ip>'));
    });

    test('has the header and only the last lines of the log', () {
      final report = buildSupportReport(
        version: '0.1.0',
        platform: 'android',
        os: 'Android 10',
        network: 'Wi-Fi',
        server: 'Авто · 🇸🇪 Швеция',
        look: 'strict, dark',
        logs: [for (var i = 0; i < 250; i++) 'line $i'],
        now: DateTime.utc(2026, 10, 23, 12),
      );
      expect(report, startsWith('TENVPN 0.1.0 · android · Android 10'));
      expect(report, contains('Сервер: Авто · 🇸🇪 Швеция'));
      expect(report, isNot(contains('line 49\n')));
      expect(report, contains('line 50'));
      expect(report, endsWith('line 249'));
    });
  });
}
