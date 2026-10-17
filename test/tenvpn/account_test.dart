import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/tenvpn/account.dart';
import 'package:fl_clash/tenvpn/awg_source.dart';
import 'package:fl_clash/tenvpn/configgen/configgen.dart';
import 'package:fl_clash/tenvpn/expiry.dart';
import 'package:fl_clash/tenvpn/presentation.dart';
import 'package:fl_clash/tenvpn/telemetry.dart';
import 'package:fl_clash/tenvpn/tenvpn_config.dart';
import 'package:fl_clash/tenvpn/tenvpn_state.dart';
import 'package:fl_clash/views/tenvpn/privacy_view.dart';
import 'package:flutter_test/flutter_test.dart';

const endpoints = TenvpnEndpoints('https://api.example.com');

Map<String, dynamic> accountJson({
  int daysLeft = 13,
  String? paidUntil = '2026-10-30',
  String status = 'active',
  String? renewUrl = 'https://t.me/Tenvpnrobot?start=app_renew',
}) => {
  'version': 1,
  'balance_rub': 91.5,
  'daily_rate_rub': 7,
  'days_left': daysLeft,
  'paid_until': ?paidUntil,
  'devices': {'active': 2},
  'status': status,
  'renew_url': ?renewUrl,
  'support_url': 'https://t.me/tenvpnsupp',
};

String fixture(String name) =>
    File('test/fixtures/tenvpn/$name').readAsStringSync();

void main() {
  group('endpoints', () {
    test('are built from the base address, trailing slash or not', () {
      final api = TenvpnEndpoints.fromBase('https://api.example.com/')!;
      expect(api.awg, 'https://api.example.com/api/app/v1/awg');
      expect(api.account, 'https://api.example.com/api/app/v1/account');
      expect(api.telemetry, 'https://api.example.com/api/app/v1/telemetry');
      expect(TenvpnEndpoints.fromBase(''), isNull);
      expect(TenvpnEndpoints.fromBase('not a url'), isNull);
      expect(TenvpnEndpoints.configured, isNull);
    });
  });

  group('AccountInfo', () {
    test('reads the contract and round-trips through the cache', () {
      final account = AccountInfo.fromJson(accountJson());
      expect(account.balanceRub, 91.5);
      expect(account.dailyRateRub, 7);
      expect(account.daysLeft, 13);
      expect(account.activeDevices, 2);
      expect(account.status, AccountStatus.active);
      expect(account.paidUntil, DateTime(2026, 10, 30));
      final again = AccountInfo.fromJson(account.toJson());
      expect(again.toJson(), account.toJson());
    });

    test('counts the end date from days_left when paid_until is absent', () {
      final account = AccountInfo.fromJson(accountJson(paidUntil: null));
      expect(
        account.expiry(DateTime(2026, 10, 17, 23, 50)),
        DateTime(2026, 10, 30),
      );
    });

    test('only https links are kept for renew and support', () {
      for (final bad in [
        'http://t.me/x',
        'javascript:alert(1)',
        'tg://resolve',
        '',
      ]) {
        expect(safeHttpsUrl(bad), isNull, reason: bad);
      }
      expect(
        AccountInfo.fromJson(
          accountJson(renewUrl: 'http://evil.example'),
        ).renewUrl,
        isNull,
      );
    });

    test('unknown status falls back to active, missing numbers fail', () {
      expect(
        AccountInfo.fromJson(accountJson(status: 'vip')).status,
        AccountStatus.active,
      );
      expect(
        () => AccountInfo.fromJson({...accountJson()}..remove('balance_rub')),
        throwsFormatException,
      );
    });
  });

  group('fetchAccount', () {
    Future<AccountFetchResult> fetch(AwgHttpResponse Function() answer) =>
        fetchAccount(endpoints, 'tok', (uri, headers) async {
          expect(uri.toString(), endpoints.account);
          expect(headers['Authorization'], 'Bearer tok');
          return answer();
        });

    test('200 with version 1 is an account', () async {
      final result = await fetch(
        () => AwgHttpResponse(200, json.encode(accountJson())),
      );
      expect(result, isA<AccountFetched>());
    });

    test('401/403/410 revoke, the rest is temporary', () async {
      for (final status in [401, 403, 410]) {
        expect(
          await fetch(() => AwgHttpResponse(status, '{}')),
          isA<AccountRevoked>(),
        );
      }
      for (final answer in [
        () => const AwgHttpResponse(503, '{}'),
        () => const AwgHttpResponse(404, '{}'),
        () => const AwgHttpResponse(200, 'nope'),
        () => const AwgHttpResponse(200, '{"version":2}'),
        () => throw const SocketException('offline'),
      ]) {
        expect(await fetch(answer), isA<AccountUnavailable>());
      }
    });
  });

  group('expiry', () {
    final now = DateTime(2026, 10, 17, 12);
    AccountCache cache(Map<String, dynamic> json) =>
        AccountCache(account: AccountInfo.fromJson(json), fetchedAt: now);

    test('the account wins over the panel date', () {
      final expiry = resolveExpiry(
        account: cache(accountJson()),
        subscription: DateTime(2027),
      );
      expect(expiry.source, ExpirySource.account);
      expect(expiry.date, DateTime(2026, 10, 30));
      final panel = resolveExpiry(subscription: DateTime(2027));
      expect(panel.source, ExpirySource.subscription);
      expect(panel.date, DateTime(2027));
    });

    test('free access has no end date and no notice', () {
      final expiry = resolveExpiry(account: cache(accountJson(status: 'free')));
      expect(expiry.date, isNull);
      expect(expiry.free, isTrue);
      expect(expiryNoticeKey(expiry, now), isNull);
    });

    test('notice from two days before the end, once per date', () {
      String? key(int days, {String? shown}) => expiryNoticeKey(
        resolveExpiry(
          account: cache(accountJson(daysLeft: days, paidUntil: null)),
        ),
        now,
        alreadyShown: shown,
      );
      expect(key(3), isNull);
      expect(key(2), '2026-10-19');
      expect(key(0), '2026-10-17');
      expect(key(2, shown: '2026-10-19'), isNull);
      expect(key(1, shown: '2026-10-19'), '2026-10-18');
      expect(
        expiryNoticeKey(
          resolveExpiry(account: cache(accountJson(status: 'suspended'))),
          DateTime(2026, 11, 2),
        ),
        '2026-10-30',
      );
    });
  });

  group('telemetry', () {
    test('protocol names, no server names or addresses', () {
      final cases = {
        const ServerEntry(name: 'a', type: 'vless', security: 'reality'):
            'vless-reality',
        const ServerEntry(name: 'b', type: 'vless', network: 'grpc'):
            'vless-grpc',
        const ServerEntry(name: 'c', type: 'vless', network: 'xhttp'):
            'vless-xhttp',
        const ServerEntry(name: 'd', type: 'vless'): 'vless-tcp',
        const ServerEntry(name: 'e', type: 'hysteria2'): 'hysteria2',
        const ServerEntry(name: 'f', type: 'wireguard', security: 'amnezia'):
            'amneziawg',
        const ServerEntry(name: 'g', type: 'wireguard'): 'wireguard',
      };
      cases.forEach((entry, protocol) {
        expect(connectionProtocol(entry), protocol);
      });
      expect(connectionProtocol(null), 'unknown');
    });

    test('the event carries exactly the documented fields', () {
      const event = ConnectEvent(
        appVersion: '0.2.0',
        platform: 'android',
        osVersion: '29',
        protocol: 'vless-reality',
      );
      expect(event.toJson().keys.toSet(), {
        'version',
        'event',
        'app_version',
        'platform',
        'os_version',
        'protocol',
      });
    });

    test('is posted with the token and never throws', () async {
      const event = ConnectEvent(
        appVersion: '0.2.0',
        platform: 'android',
        osVersion: '29',
        protocol: 'hysteria2',
      );
      Map<String, String>? sentHeaders;
      String? sentBody;
      final ok = await sendConnectEvent(endpoints, 'tok', event, (
        uri,
        headers,
        body,
      ) async {
        expect(uri.toString(), endpoints.telemetry);
        sentHeaders = headers;
        sentBody = body;
        return const AwgHttpResponse(204, '');
      });
      expect(ok, isTrue);
      expect(sentHeaders?['Authorization'], 'Bearer tok');
      expect(json.decode(sentBody!), event.toJson());
      final failed = await sendConnectEvent(
        endpoints,
        'tok',
        event,
        (_, _, _) async => throw const SocketException('offline'),
      );
      expect(failed, isFalse);
    });

    test('one event per protocol per window', () {
      var now = DateTime(2026, 10, 17, 12);
      final throttle = TelemetryThrottle(now: () => now);
      expect(throttle.allow('vless-reality'), isTrue);
      expect(throttle.allow('vless-reality'), isFalse);
      expect(throttle.allow('hysteria2'), isTrue);
      now = now.add(const Duration(minutes: 31));
      expect(throttle.allow('vless-reality'), isTrue);
    });
  });

  group('import link', () {
    test('tenvpn://import carries the subscription and the device token', () {
      final link = parseImportLink(
        'tenvpn://import?sub=https%3A%2F%2Fsub.example.com%2Fabc&token=t0k',
      );
      expect(link?.url, 'https://sub.example.com/abc');
      expect(link?.token, 't0k');
      expect(link?.awg, isNull);
      expect(
        parseImportLink('tenvpn://import?sub=https://sub.example.com/a')?.token,
        isNull,
      );
      expect(parseImportLink('tenvpn://import?token=t'), isNull);
      expect(parseImportLink('tenvpn://import?sub=nope&token=t'), isNull);
      expect(
        parseImportLink(
          'tenvpn://import?sub=tenvpn%3A%2F%2Fimport%3Fsub%3Dhttps%3A%2F%2Fa.example.com%26token%3Dx&token=y',
        ),
        isNull,
      );
    });
  });

  group('service with a device token', () {
    late Directory dir;
    late List<String> requested;
    late Map<String, AwgHttpResponse Function()> answers;
    late TenvpnConfigService service;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('tenvpn_account_test');
      requested = [];
      answers = {};
      service = TenvpnConfigService(
        store: TenvpnStateStore(() async => dir.path),
        endpoints: endpoints,
        transport: (uri, headers) async {
          requested.add(uri.path);
          expect(headers['Authorization'], 'Bearer tok');
          return answers[uri.path]!();
        },
        now: () => DateTime.utc(2026, 10, 17),
      );
    });

    tearDown(() => dir.deleteSync(recursive: true));

    AwgHttpResponse awgOk() => AwgHttpResponse(
      200,
      json.encode({'version': 1, 'conf': fixture('awg_v2.conf')}),
    );

    test('one token fetches AWG and the account together', () async {
      await service.setAppToken(1, 'tok');
      answers['/api/app/v1/awg'] = awgOk;
      answers['/api/app/v1/account'] = () =>
          AwgHttpResponse(200, json.encode(accountJson()));
      await service.generate(1, fixture('remnawave_mihomo.yaml'));
      expect(requested.toSet(), {'/api/app/v1/awg', '/api/app/v1/account'});
      expect((await service.account(1))?.account.balanceRub, 91.5);
      expect(await service.appToken(1), 'tok');
      expect((await service.servers(1)).last.security, 'amnezia');
    });

    test('a rejected token clears the account, an outage keeps it', () async {
      await service.setAppToken(1, 'tok');
      answers['/api/app/v1/account'] = () =>
          AwgHttpResponse(200, json.encode(accountJson()));
      expect(await service.refreshAccount(1), isNotNull);
      answers['/api/app/v1/account'] = () => const AwgHttpResponse(503, '');
      expect(await service.refreshAccount(1), isNotNull);
      answers['/api/app/v1/account'] = () => const AwgHttpResponse(401, '');
      expect(await service.refreshAccount(1), isNull);
    });

    test('the notice marker survives a reload', () async {
      await service.markExpiryNotice(1, '2026-10-19');
      expect(await service.expiryNoticeFor(1), '2026-10-19');
    });

    test('without a token nothing is requested', () async {
      expect(await service.refreshAccount(1), isNull);
      await service.generate(1, fixture('remnawave_mihomo.yaml'));
      expect(requested, isEmpty);
    });
  });

  group('privacy policy', () {
    final source = File('docs/privacy.md').readAsStringSync();

    test('is bilingual and parses into headings and bullets', () {
      final blocks = parsePrivacyMarkdown(source);
      final titles = blocks
          .where((b) => b.kind == PrivacyBlockKind.title)
          .map((b) => b.text);
      expect(titles, [
        'Политика конфиденциальности TENVPN',
        'TENVPN Privacy Policy',
      ]);
      expect(
        blocks.where((b) => b.kind == PrivacyBlockKind.bullet),
        isNotEmpty,
      );
      expect(
        blocks.map((b) => b.text).join('\n'),
        contains('@tenvpnsupp (https://t.me/tenvpnsupp)'),
      );
    });

    test('names every telemetry field and avoids store-sensitive words', () {
      for (final word in [
        'обход',
        'РКН',
        'блокиров',
        'mihomo',
        'clash',
        'bypass',
      ]) {
        expect(source.toLowerCase(), isNot(contains(word.toLowerCase())));
      }
      for (final field in [
        'версию приложения',
        'платформу',
        'версию системы',
        'протокола',
      ]) {
        expect(source, contains(field));
      }
    });

    test('is bundled with the app', () {
      expect(
        File('pubspec.yaml').readAsStringSync(),
        contains('- $privacyAsset'),
      );
    });
  });
}
