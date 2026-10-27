import 'dart:convert';
import 'dart:io';

import 'package:fl_clash/tenvpn/awg_source.dart';
import 'package:fl_clash/tenvpn/configgen/configgen.dart';
import 'package:fl_clash/tenvpn/headers.dart';
import 'package:fl_clash/tenvpn/tenvpn_config.dart';
import 'package:fl_clash/tenvpn/tenvpn_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

String fixture(String name) =>
    File('test/fixtures/tenvpn/$name').readAsStringSync();

const source = AwgSource(
  url: 'https://api.example.com/api/app/v1/awg',
  token: 't0k',
);

void main() {
  late Directory dir;
  late TenvpnStateStore store;
  late List<AwgHttpResponse Function()> responses;
  late List<Map<String, String>> requests;
  late List<String> logs;
  late TenvpnConfigService service;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('tenvpn_config_test');
    store = TenvpnStateStore(() async => dir.path);
    responses = [];
    requests = [];
    logs = [];
    service = TenvpnConfigService(
      store: store,
      transport: (uri, headers) async {
        requests.add({'uri': uri.toString(), ...headers});
        return responses.removeAt(0)();
      },
      now: () => DateTime.utc(2026, 10, 17),
      log: logs.add,
    );
  });

  tearDown(() => dir.deleteSync(recursive: true));

  AwgHttpResponse awgOk([String? name]) => AwgHttpResponse(
    200,
    json.encode({
      'version': 1,
      'name': ?name,
      'protocol': '2.0',
      'conf': fixture('awg_v2.conf'),
    }),
  );

  List<String> proxyNames(String yaml) => [
    for (final proxy in (loadYaml(yaml)['proxies'] as YamlList))
      proxy['name'] as String,
  ];

  test(
    'a settings change rebuilds offline from the cached subscription',
    () async {
      expect(await service.regenerate(1), isNull);
      await service.setAwgSource(1, source);
      responses.add(() => awgOk('AWG NL'));
      await service.generate(1, fixture('remnawave_mihomo.yaml'));
      expect(requests, hasLength(1));

      var russianDirect = false;
      final offline = TenvpnConfigService(
        store: store,
        transport: (uri, headers) => fail('no network on regenerate'),
        options: () => ConfigGenOptions(russianDirect: russianDirect),
      );
      final rebuilt = await offline.regenerate(1);
      final rules = (loadYaml(rebuilt!)['rules'] as YamlList).cast<String>();
      expect(rules.where((rule) => rule.startsWith('DOMAIN-SUFFIX')), isEmpty);
      expect(proxyNames(rebuilt).last, 'AWG NL');
      russianDirect = true;
      final again =
          (loadYaml((await offline.regenerate(1))!)['rules'] as YamlList)
              .cast<String>();
      expect(again, contains('DOMAIN-SUFFIX,gosuslugi.ru,DIRECT'));

      await service.forget(1);
      expect(await service.regenerate(1), isNull);
      expect(dir.listSync(), isEmpty);
    },
  );

  test(
    'an Amnezia key alone is a whole profile and rebuilds offline',
    () async {
      final yaml = await service.generateAwgOnly(7, fixture('awg_v3.conf'));
      expect(requests, isEmpty);
      final config = loadYaml(yaml);
      expect(proxyNames(yaml), [awgDefaultName]);
      final groups = {
        for (final group in (config['proxy-groups'] as YamlList))
          group['name'] as String: group,
      };
      expect((groups[autoGroupName]['proxies'] as YamlList).toList(), [
        awgDefaultName,
      ]);
      expect((groups[manualGroupName]['proxies'] as YamlList).toList(), [
        awgDefaultName,
      ]);
      expect(proxyNames((await service.regenerate(7))!), [awgDefaultName]);
      expect(await service.hasManualAwg(7), isTrue);
    },
  );

  test(
    'a pasted AWG key wins over the server source and is not fetched',
    () async {
      await service.setAwgSource(1, source);
      await service.setManualAwg(1, fixture('awg_v3.conf'));
      expect(await service.hasManualAwg(1), isTrue);
      final yaml = await service.generate(1, fixture('remnawave_mihomo.yaml'));
      expect(requests, isEmpty);
      expect(proxyNames(yaml).last, awgDefaultName);
      expect(await service.regenerate(1), contains(awgDefaultName));

      await expectLater(
        service.setManualAwg(1, '[Interface]\nPrivateKey = x'),
        throwsA(isA<ConfigGenException>()),
      );
      expect(await service.hasManualAwg(1), isTrue);
      await service.setManualAwg(1, null);
      expect(await service.hasManualAwg(1), isFalse);
      expect(logs.join(), isNot(contains('PrivateKey')));
    },
  );

  test('without an AWG source the subscription alone is used', () async {
    final yaml = await service.generate(1, fixture('remnawave_mihomo.yaml'));
    expect(proxyNames(yaml), hasLength(8));
    expect(requests, isEmpty);
    final servers = await service.servers(1);
    expect(servers.map((server) => server.name), proxyNames(yaml));
  });

  test('fetches AWG with the bearer token and caches it', () async {
    await service.setAwgSource(1, source);
    responses.add(() => awgOk('AWG NL'));
    final yaml = await service.generate(1, fixture('remnawave_mihomo.yaml'));
    expect(proxyNames(yaml).last, 'AWG NL');
    expect(requests.single['uri'], source.url);
    expect(requests.single['Authorization'], 'Bearer t0k');
    final state = await store.load(1);
    expect(state.awgCache?.name, 'AWG NL');
    expect(state.awgCache?.fetchedAt, DateTime.utc(2026, 10, 17));
    expect((await service.servers(1)).last.section, awgSectionTitle);
  });

  test('a network failure or 5xx keeps the cached AWG profile', () async {
    await service.setAwgSource(1, source);
    responses
      ..add(awgOk)
      ..add(() => throw const SocketException('offline'))
      ..add(() => const AwgHttpResponse(503, '{"error":"awg_unavailable"}'))
      ..add(() => const AwgHttpResponse(200, 'not json'));
    for (var i = 0; i < 4; i++) {
      final yaml = await service.generate(1, fixture('remnawave_mihomo.yaml'));
      expect(proxyNames(yaml).last, awgDefaultName, reason: 'run $i');
    }
    expect(logs, hasLength(3));
  });

  for (final status in [401, 403, 404, 410]) {
    test(
      'HTTP $status from the backend drops the cached AWG profile',
      () async {
        await service.setAwgSource(1, source);
        responses
          ..add(awgOk)
          ..add(() => AwgHttpResponse(status, '{}'));
        await service.generate(1, fixture('remnawave_mihomo.yaml'));
        final yaml = await service.generate(
          1,
          fixture('remnawave_mihomo.yaml'),
        );
        expect(proxyNames(yaml), isNot(contains(awgDefaultName)));
        expect((await store.load(1)).awgCache, isNull);
      },
    );
  }

  test(
    'an invalid AWG profile from the backend never replaces the cache',
    () async {
      await service.setAwgSource(1, source);
      responses
        ..add(awgOk)
        ..add(
          () => AwgHttpResponse(
            200,
            json.encode({'version': 1, 'conf': '[Interface]\nPrivateKey = x'}),
          ),
        );
      await service.generate(1, fixture('remnawave_mihomo.yaml'));
      final yaml = await service.generate(1, fixture('remnawave_mihomo.yaml'));
      expect(proxyNames(yaml).last, awgDefaultName);
    },
  );

  test('a broken subscription fails before the AWG request', () async {
    await service.setAwgSource(1, source);
    await expectLater(
      service.generate(1, fixture('remnawave_base64.txt')),
      throwsA(
        isA<ConfigGenException>().having(
          (e) => e.code,
          'code',
          ConfigGenErrorCode.shareLinks,
        ),
      ),
    );
    expect(requests, isEmpty);
  });

  test('removing the source and forgetting the profile clear state', () async {
    await service.setAwgSource(1, source);
    responses.add(awgOk);
    await service.generate(1, fixture('remnawave_mihomo.yaml'));
    await service.setAwgSource(1, null);
    final yaml = await service.generate(1, fixture('remnawave_mihomo.yaml'));
    expect(proxyNames(yaml), isNot(contains(awgDefaultName)));
    await service.forget(1);
    expect(File('${dir.path}/1.json').existsSync(), isFalse);
  });

  test('a corrupt state file is treated as empty', () async {
    File('${dir.path}/1.json').writeAsStringSync('{torn');
    final state = await store.load(1);
    expect(state.awgSource, isNull);
    expect(state.servers, isEmpty);
  });

  group('subscription headers', () {
    test('profile-title', () {
      expect(parseProfileTitle('base64:VEVOIFZQTg=='), 'TEN VPN');
      expect(parseProfileTitle('TENVPN'), 'TENVPN');
      expect(parseProfileTitle('base64:%%%'), isNull);
      expect(parseProfileTitle(null), isNull);
    });

    test('profile-update-interval is clamped to 1–24 hours', () {
      expect(parseUpdateInterval('1'), const Duration(hours: 1));
      expect(parseUpdateInterval('12'), const Duration(hours: 12));
      expect(parseUpdateInterval('720'), const Duration(hours: 24));
      expect(parseUpdateInterval('0'), isNull);
      expect(parseUpdateInterval('soon'), isNull);
      expect(parseUpdateInterval(null), isNull);
    });
  });
}
