import 'dart:io';
import 'dart:math';

import 'package:fl_clash/tenvpn/configgen/configgen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

String fixture(String name) =>
    File('test/fixtures/tenvpn/$name').readAsStringSync();

Map<String, dynamic> proxyNamed(
  List<Map<String, dynamic>> proxies,
  String name,
) => proxies.firstWhere((proxy) => proxy['name'] == name);

Map<String, dynamic> roundTrip(GeneratedConfig generated) =>
    toPlain(loadYaml(encodeConfig(generated))) as Map<String, dynamic>;

Matcher throwsConfigGen(ConfigGenErrorCode code) =>
    throwsA(isA<ConfigGenException>().having((e) => e.code, 'code', code));

void main() {
  group('parseSubscription', () {
    late Map<String, dynamic> raw;
    late ParsedSubscription parsed;

    setUp(() {
      raw =
          toPlain(loadYaml(fixture('remnawave_mihomo.yaml')))
              as Map<String, dynamic>;
      parsed = parseSubscription(fixture('remnawave_mihomo.yaml'));
    });

    test('keeps every real proxy and drops the separator', () {
      expect(parsed.proxies, hasLength(8));
      expect(parsed.separators, [
        '🇻🇳  👇 Серверы для обхода белых списков 👇',
      ]);
      expect(
        parsed.proxies.map((proxy) => proxy['name']),
        isNot(contains(parsed.separators.single)),
      );
    });

    test('copies proxies field for field', () {
      final rawProxies = (raw['proxies'] as List)
          .cast<Map<String, dynamic>>()
          .where((proxy) => proxy['server'] != '127');
      for (final original in rawProxies) {
        expect(
          proxyNamed(parsed.proxies, original['name'] as String),
          equals(original),
        );
      }
    });

    test('tags servers after a separator with its section', () {
      final sections = {
        for (final server in parsed.servers) server.name: server.section,
      };
      expect(sections['🇳🇱 ⚡ Нидерланды'], isNull);
      expect(
        sections['🇪🇺  Обход белых списков 1'],
        'Серверы для обхода белых списков',
      );
      expect(parsed.servers.map((server) => server.transport).toSet(), {
        'ws',
        'vless',
        'hysteria2',
        'grpc',
        'xhttp',
      });
    });

    test('base64 share links fail with a dedicated error', () {
      expect(
        () => parseSubscription(fixture('remnawave_base64.txt')),
        throwsConfigGen(ConfigGenErrorCode.shareLinks),
      );
      expect(
        () => parseSubscription('vless://id@host:443#a\nvless://id@host:443#b'),
        throwsConfigGen(ConfigGenErrorCode.shareLinks),
      );
    });

    test('other unusable bodies fail instead of importing nothing', () {
      expect(
        () => parseSubscription('  \n'),
        throwsConfigGen(ConfigGenErrorCode.empty),
      );
      expect(
        () => parseSubscription('<!DOCTYPE html><html><body>404</body></html>'),
        throwsConfigGen(ConfigGenErrorCode.html),
      );
      expect(
        () => parseSubscription('proxies: [unclosed'),
        throwsConfigGen(ConfigGenErrorCode.invalidYaml),
      );
      expect(
        () => parseSubscription('- just\n- a list\n'),
        throwsConfigGen(ConfigGenErrorCode.notAConfig),
      );
      expect(
        () => parseSubscription('mode: rule\nproxies: []\n'),
        throwsConfigGen(ConfigGenErrorCode.noProxies),
      );
      expect(
        () => parseSubscription(
          "proxies:\n  - {name: only separator, type: vless, server: '127'}\n",
        ),
        throwsConfigGen(ConfigGenErrorCode.noProxies),
      );
    });

    test('renames duplicates and proxies that clash with our groups', () {
      final parsed = parseSubscription('''
proxies:
  - {name: A, type: vless, server: a.example.com, port: 443}
  - {name: A, type: vless, server: b.example.com, port: 443}
  - {name: Авто, type: vless, server: c.example.com, port: 443}
  - {name: DIRECT, type: vless, server: d.example.com, port: 443}
''');
      expect(parsed.proxies.map((proxy) => proxy['name']), [
        'A',
        'A (2)',
        'Авто (2)',
        'DIRECT (2)',
      ]);
    });

    test('isRoutableHost', () {
      for (final host in [
        'example.com',
        '192.0.2.1',
        '2001:db8::1',
        'a.b-c.io',
      ]) {
        expect(isRoutableHost(host), isTrue, reason: host);
      }
      for (final host in [
        '127',
        '',
        '0.0.0.0',
        '127.0.0.1',
        '999.1.1.1',
        'localhost',
        null,
      ]) {
        expect(isRoutableHost(host), isFalse, reason: '$host');
      }
    });
  });

  group('parseAwgConf', () {
    test('AmneziaWG 2.0 profile with header ranges and CPS', () {
      final proxy = parseAwgConf(fixture('awg_v2.conf'));
      expect(proxy, {
        'name': awgDefaultName,
        'type': 'wireguard',
        'server': '192.0.2.50',
        'port': 47213,
        'ip': '10.66.0.42',
        'private-key': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
        'public-key': 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBA=',
        'pre-shared-key': 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCA=',
        'allowed-ips': ['0.0.0.0/0'],
        'udp': true,
        'mtu': 1280,
        'persistent-keepalive': 25,
        'remote-dns-resolve': true,
        'dns': ['1.1.1.1', '1.0.0.1'],
        'amnezia-wg-option': {
          'jc': 4,
          'jmin': 40,
          'jmax': 70,
          's1': 15,
          's2': 23,
          's3': 18,
          's4': 9,
          'h1': '172006388-202361271',
          'h2': '471800590-525218421',
          'h3': '1063457287-1121234560',
          'h4': '1903204218-2004318222',
          'i1': '<b 0xc2000000011e><r 16><t>',
        },
      });
    });

    test('AmneziaWG 1.x profile with IPv6 endpoint and dual-stack address', () {
      final proxy = parseAwgConf(fixture('awg_v1.conf'), name: 'AWG');
      expect(proxy['name'], 'AWG');
      expect(proxy['server'], '2001:db8::50');
      expect(proxy['port'], 47214);
      expect(proxy['ip'], '10.67.0.7');
      expect(proxy['ipv6'], 'fd00:67::7');
      expect(proxy['allowed-ips'], ['0.0.0.0/0', '::/0']);
      expect(proxy.containsKey('pre-shared-key'), isFalse);
      expect(proxy['amnezia-wg-option'], {
        'jc': 4,
        'jmin': 40,
        'jmax': 70,
        's1': 15,
        's2': 23,
        'h1': '1000001',
        'h2': '1000002',
        'h3': '1000003',
        'h4': '1000004',
      });
    });

    test('AmneziaWG 3.1 profile switches the core to version 3', () {
      final proxy = parseAwgConf(fixture('awg_v3.conf'));
      expect(proxy['amnezia-wg-option'], {
        'jc': 4,
        'jmin': 40,
        'jmax': 70,
        's1': 15,
        's2': 23,
        's3': 18,
        's4': 16,
        'h1': '172006388-202361271',
        'h2': '471800590-525218421',
        'h3': '1063457287-1121234560',
        'h4': '1903204218-2004318222',
        'i1': '<b 0xc2000000011e><r 16><t>',
        'header-protection-key': 'DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDA=',
        'content-padding-addition': '2-10',
        'random-trailers': true,
        'version': 3,
      });
    });

    test('3.x drops the 1.5-only fields, a zero padding stays 2.0', () {
      final v3 = fixture(
        'awg_v3.conf',
      ).replaceFirst('I1 = ', 'J1 = <r 8>\nItime = 120\nI1 = ');
      final option = parseAwgConf(v3)['amnezia-wg-option'] as Map;
      expect(option.containsKey('j1'), isFalse);
      expect(option.containsKey('itime'), isFalse);
      expect(option['version'], 3);

      final v2 = fixture(
        'awg_v2.conf',
      ).replaceFirst('I1 = ', 'ContentPaddingAddition = 0\nI1 = ');
      final legacy = parseAwgConf(v2)['amnezia-wg-option'] as Map;
      expect(legacy.containsKey('version'), isFalse);
      expect(legacy.containsKey('content-padding-addition'), isFalse);
    });

    test('plain WireGuard has no amnezia options', () {
      final conf = fixture('awg_v1.conf').replaceAll(
        RegExp(r'^(Jc|Jmin|Jmax|S1|S2|H\d) = .*\r?\n', multiLine: true),
        '',
      );
      expect(parseAwgConf(conf).containsKey('amnezia-wg-option'), isFalse);
    });

    test('rejects broken profiles', () {
      final v2 = fixture('awg_v2.conf');
      for (final broken in [
        '',
        v2.replaceAll('[Peer]', '[Other]'),
        v2.replaceFirst(RegExp(r'PrivateKey = .*'), 'PrivateKey = short'),
        v2.replaceFirst(RegExp(r'Endpoint = .*'), 'Endpoint = 192.0.2.50'),
        v2.replaceFirst(RegExp(r'Address = .*'), ''),
        v2.replaceFirst('Jc = 4', 'Jc = four'),
        v2.replaceFirst(RegExp(r'H1 = .*'), 'H1 = 1-two'),
        fixture('awg_v3.conf').replaceFirst(
          RegExp(r'HeaderProtectionKey = .*'),
          'HeaderProtectionKey = short',
        ),
        fixture('awg_v3.conf').replaceFirst('2-10', 'two-ten'),
        fixture(
          'awg_v3.conf',
        ).replaceFirst('RandomTrailers = on', 'RandomTrailers = maybe'),
      ]) {
        expect(
          () => parseAwgConf(broken),
          throwsConfigGen(ConfigGenErrorCode.awgInvalid),
        );
      }
    });
  });

  group('buildConfig', () {
    late ParsedSubscription subscription;

    setUp(() {
      subscription = parseSubscription(fixture('remnawave_mihomo.yaml'));
    });

    test('groups: TENVPN → Авто (regular → whitelist tiers) / Вручную', () {
      final generated = buildConfig(subscription);
      final groups = (generated.config['proxy-groups'] as List)
          .cast<Map<String, dynamic>>();
      final names = subscription.proxies.map((proxy) => proxy['name']).toList();
      expect(groups.map((group) => group['name']), [
        mainGroupName,
        autoGroupName,
        autoPrimaryGroupName,
        autoWhitelistGroupName,
        manualGroupName,
      ]);
      expect(groups[0]['type'], 'select');
      expect(groups[0]['proxies'], [autoGroupName, manualGroupName]);
      expect(groups[1], {
        'name': autoGroupName,
        'type': 'fallback',
        'proxies': [autoPrimaryGroupName, autoWhitelistGroupName],
        'url': 'https://www.gstatic.com/generate_204',
        'expected-status': '204',
        'interval': 15,
        'timeout': 5000,
        'lazy': true,
        'max-failed-times': 3,
      });
      expect(groups[2], {
        'name': autoPrimaryGroupName,
        'type': 'url-test',
        'proxies': names.take(6).toList(),
        'url': 'https://www.gstatic.com/generate_204',
        'expected-status': '204',
        'interval': 120,
        'timeout': 3000,
        'tolerance': 100,
        'lazy': true,
        'max-failed-times': 3,
        'hidden': true,
      });
      expect(groups[3]['type'], 'url-test');
      expect(groups[3]['proxies'], [
        '🇪🇺  Обход белых списков 1',
        '🇪🇺 Обход белых списков 2',
      ]);
      expect(groups[3]['interval'], 300);
      expect(groups[3]['timeout'], 5000);
      expect(groups[3]['tolerance'], 150);
      expect(groups[3]['hidden'], isTrue);
      expect(groups[3].containsKey('max-failed-times'), isFalse);
      expect(groups[4]['type'], 'select');
      expect(groups[4]['proxies'], names);
      expect(generated.config['rules'].last, 'MATCH,$mainGroupName');
      expect(generated.config['mode'], 'rule');
    });

    test('battery saver checks rarely but still leaves failing servers', () {
      final groups =
          (buildConfig(
                    subscription,
                    options: const ConfigGenOptions.saver(),
                  ).config['proxy-groups']
                  as List)
              .cast<Map<String, dynamic>>();
      expect(
        [for (final g in groups.sublist(1, 4)) g['interval']],
        [300, 900, 1800],
      );
      expect(groups[1]['max-failed-times'], 3);
      expect(groups[2]['max-failed-times'], 3);
    });

    test('one tier and no AWG: «Авто» is that url-test itself', () {
      for (final (text, wl) in [
        (
          'proxies:\n'
              '  - {name: A, type: vless, server: a.example.com, port: 443}\n'
              '  - {name: B, type: vless, server: b.example.com, port: 443}\n',
          false,
        ),
        (
          'proxies:\n'
              '  - {name: Белые списки 1, type: vless, server: a.example.com, port: 443}\n',
          true,
        ),
      ]) {
        final groups =
            (buildConfig(parseSubscription(text)).config['proxy-groups']
                    as List)
                .cast<Map<String, dynamic>>();
        expect(groups.map((group) => group['name']), [
          mainGroupName,
          autoGroupName,
          manualGroupName,
        ]);
        expect(groups[1]['type'], 'url-test');
        expect(groups[1].containsKey('hidden'), isFalse);
        expect(groups[1]['interval'], wl ? 300 : 120);
      }
    });

    test('a whitelist server is found by its name outside the section', () {
      final groups = {
        for (final group
            in buildConfig(
                  parseSubscription('''
proxies:
  - {name: NL, type: vless, server: a.example.com, port: 443}
  - {name: 🇪🇺 Обход белых списков 9, type: vless, server: b.example.com, port: 443}
'''),
                ).config['proxy-groups']
                as List)
          group['name']: group,
      };
      expect(groups[autoPrimaryGroupName]['proxies'], ['NL']);
      expect(groups[autoWhitelistGroupName]['proxies'], [
        '🇪🇺 Обход белых списков 9',
      ]);
      expect(
        isWhitelistServer(const ServerEntry(name: 'X', type: 'vless')),
        isFalse,
      );
      expect(
        isWhitelistServer(
          const ServerEntry(
            name: 'X',
            type: 'vless',
            section: 'Серверы для обхода белых списков',
          ),
        ),
        isTrue,
      );
    });

    test('tun, fake-ip DNS without Chinese resolvers, controller secret', () {
      final generated = buildConfig(subscription, random: Random(1));
      final config = generated.config;
      expect(config['tun']['enable'], isTrue);
      expect(config['tun']['dns-hijack'], ['any:53']);
      final dns = config['dns'] as Map<String, dynamic>;
      expect(dns['enhanced-mode'], 'fake-ip');
      final resolvers = [
        ...dns['default-nameserver'],
        ...dns['nameserver'],
        ...dns['proxy-server-nameserver'],
      ].join(' ');
      for (final chinese in [
        '223.5.5.5',
        '119.29',
        'doh.pub',
        'alidns',
        '114.114',
      ]) {
        expect(resolvers, isNot(contains(chinese)));
      }
      expect(dns.containsKey('nameserver-policy'), isFalse);
      expect(dns['listen'], '127.0.0.1:1053');
      for (final server in dns['nameserver'] as List) {
        expect(server, endsWith('#$mainGroupName'), reason: 'through the VPN');
      }
      expect(dns['proxy-server-nameserver'].first, '77.88.8.8');
      expect(dns['direct-nameserver'], dns['proxy-server-nameserver']);
      expect(config['external-controller'], '127.0.0.1:9090');
      expect(generated.secret, matches(RegExp(r'^[0-9a-f]{32}$')));
      expect(config['secret'], generated.secret);
      expect(
        buildConfig(subscription).secret,
        isNot(buildConfig(subscription).secret),
      );
    });

    test('AWG stays out of «Авто» and is picked by hand in «Вручную»', () {
      final awg = parseAwgConf(fixture('awg_v2.conf'));
      final generated = buildConfig(subscription, awg: awg);
      final groups = {
        for (final group in (generated.config['proxy-groups'] as List))
          group['name']: group,
      };
      expect(groups[autoGroupName]['proxies'], [
        autoPrimaryGroupName,
        autoWhitelistGroupName,
      ]);
      final regularOnly = buildConfig(
        parseSubscription(
          'proxies:\n'
          '  - {name: A, type: vless, server: a.example.com, port: 443}\n',
        ),
        awg: awg,
      );
      final auto = (regularOnly.config['proxy-groups'] as List)[1];
      expect(auto['type'], 'url-test');
      expect(auto['proxies'], ['A']);
      for (final tier in autoTierGroupNames) {
        expect(groups[tier]['proxies'], isNot(contains(awgDefaultName)));
      }
      expect(groups[manualGroupName]['proxies'].last, awgDefaultName);
      expect(generated.servers.last.section, awgSectionTitle);
      expect(
        proxyNamed(
          (generated.config['proxies'] as List).cast<Map<String, dynamic>>(),
          awgDefaultName,
        ),
        awg,
      );
    });

    test('awgFirst puts AWG ahead of both tiers', () {
      final awg = parseAwgConf(fixture('awg_v2.conf'));
      final generated = buildConfig(
        subscription,
        awg: awg,
        options: const ConfigGenOptions(autoStrategy: AutoStrategy.awgFirst),
      );
      final groups = {
        for (final group in (generated.config['proxy-groups'] as List))
          group['name']: group,
      };
      expect(groups[autoGroupName]['type'], 'fallback');
      expect(groups[autoGroupName]['proxies'], [
        awgDefaultName,
        autoPrimaryGroupName,
        autoWhitelistGroupName,
      ]);
      final withoutAwg = buildConfig(
        subscription,
        options: const ConfigGenOptions(autoStrategy: AutoStrategy.awgFirst),
      );
      expect((withoutAwg.config['proxy-groups'] as List)[1]['proxies'], [
        autoPrimaryGroupName,
        autoWhitelistGroupName,
      ]);
    });
  });

  group('Russian services directly', () {
    List<String> rulesOf(ConfigGenOptions options) =>
        (buildConfig(
                  parseSubscription(fixture('remnawave_mihomo.yaml')),
                  options: options,
                ).config['rules']
                as List)
            .cast<String>();

    test('on by default: DIRECT suffix rules between LAN and MATCH', () {
      final rules = rulesOf(const ConfigGenOptions());
      final direct = [
        for (final rule in rules)
          if (rule.startsWith('DOMAIN-SUFFIX,')) rule,
      ];
      expect(direct, [
        for (final domain in russianDirectDomains)
          'DOMAIN-SUFFIX,$domain,DIRECT',
      ]);
      for (final service in ['gosuslugi.ru', 'sberbank.ru', 'ozon.ru']) {
        expect(rules, contains('DOMAIN-SUFFIX,$service,DIRECT'));
      }
      expect(rules.take(privateNetworkRules.length), privateNetworkRules);
      expect(rules.indexOf(direct.last), rules.length - 2);
      expect(rules.last, 'MATCH,$mainGroupName');
    });

    test('off: everything goes through the VPN', () {
      expect(rulesOf(const ConfigGenOptions(russianDirect: false)), [
        ...privateNetworkRules,
        'MATCH,$mainGroupName',
      ]);
    });

    test('a short list, never the whole zone or geoip', () {
      expect(
        russianDirectDomains.toSet(),
        hasLength(russianDirectDomains.length),
      );
      for (final domain in russianDirectDomains) {
        expect(domain, matches(RegExp(r'^[a-z0-9-]+(\.[a-z0-9-]+)+$')));
        expect(['ru', 'su', 'xn--p1ai', 'рф'], isNot(contains(domain)));
        expect(domain, isNot(contains('pikabu')));
      }
      final rules = rulesOf(const ConfigGenOptions()).join('\n');
      expect(rules, isNot(contains('GEOIP')));
      expect(rules, isNot(contains('DOMAIN-SUFFIX,ru,')));
    });
  });

  group('alignWithXray', () {
    late List<Map<String, dynamic>> proxies;

    setUp(() {
      proxies =
          (buildConfig(
                    parseSubscription(fixture('remnawave_mihomo.yaml')),
                  ).config['proxies']
                  as List)
              .cast<Map<String, dynamic>>();
    });

    test('empty xhttp padding fields get the Xray defaults', () {
      final second = proxyNamed(proxies, '🇪🇺 Обход белых списков 2');
      expect(
        second['xhttp-opts'],
        containsPair('x-padding-header', 'X-Padding'),
      );
      expect(second['xhttp-opts'], containsPair('x-padding-key', 'x_padding'));
      expect(
        second['xhttp-opts'],
        containsPair('x-padding-placement', 'header'),
      );
      expect(
        second['xhttp-opts'],
        containsPair('x-padding-method', 'tokenish'),
      );
      final first = proxyNamed(proxies, '🇪🇺  Обход белых списков 1');
      expect(
        first['xhttp-opts'],
        containsPair('x-padding-header', 'X-Cache-Token'),
      );
      expect(first['xhttp-opts'], containsPair('x-padding-key', 'tag'));
      expect(first['client-fingerprint'], 'firefox');
      final plain = alignWithXray({
        'name': 'X',
        'xhttp-opts': {'path': '/', 'x-padding-header': ''},
      });
      expect(plain['xhttp-opts'], {'path': '/', 'x-padding-header': ''});
      final bare = alignWithXray({
        'name': 'Y',
        'xhttp-opts': {'x-padding-obfs-mode': true, 'x-padding-key': ''},
      });
      expect(bare['xhttp-opts'], {
        'x-padding-obfs-mode': true,
        ...xrayPaddingDefaults,
      });
    });

    test('Reality keeps its fingerprint; ML-KEM only when asked', () {
      final raw = parseSubscription(fixture('remnawave_mihomo.yaml')).proxies;
      final reality = proxies.where((proxy) => proxy['reality-opts'] != null);
      expect(reality, hasLength(3));
      for (final proxy in reality) {
        final original = proxyNamed(raw, proxy['name'] as String);
        expect(proxy['client-fingerprint'], original['client-fingerprint']);
        expect(proxy['reality-opts'], original['reality-opts']);
      }
      final withMlkem =
          (buildConfig(
                    parseSubscription(fixture('remnawave_mihomo.yaml')),
                    options: const ConfigGenOptions(realityMlkem: true),
                  ).config['proxies']
                  as List)
              .cast<Map<String, dynamic>>();
      for (final proxy in withMlkem.where((p) => p['reality-opts'] != null)) {
        expect(proxy['client-fingerprint'], 'chrome', reason: proxy['name']);
        expect(proxy['reality-opts']['support-x25519mlkem768'], isTrue);
        expect(proxy['reality-opts'], contains('public-key'));
      }
      final hysteria = proxyNamed(proxies, '🇳🇱 ⚡ Нидерланды (Hysteria2) 🚀');
      expect(hysteria.containsKey('reality-opts'), isFalse);
    });

    test('the subscription itself is left untouched', () {
      final parsed = parseSubscription(fixture('remnawave_mihomo.yaml'));
      buildConfig(parsed);
      final second = proxyNamed(parsed.proxies, '🇪🇺 Обход белых списков 2');
      expect(second['xhttp-opts'], isNot(contains('x-padding-header')));
    });
  });

  group('encoded YAML', () {
    test('round-trips every fragile field, xhttp and xmux included', () {
      final awg = parseAwgConf(fixture('awg_v2.conf'));
      final generated = generateFromSubscription(
        fixture('remnawave_mihomo.yaml'),
        awg: awg,
      );
      expect(roundTrip(generated), equals(generated.config));
    });

    test('keeps strings that YAML 1.1 would retype', () {
      final text = encodeConfig(
        generateFromSubscription(fixture('remnawave_mihomo.yaml')),
      );
      expect(text, contains(RegExp(r'''seq-key: ['"]n['"]''')));
      expect(text, contains(RegExp(r'''max-connections: ['"]0['"]''')));
      expect(text, contains(RegExp(r'''short-id: ['"]01234567['"]''')));
      expect(text, contains(RegExp(r'''short-id: ['"]{2}''')));
    });
  });

  test('every error code has a Russian message', () {
    for (final code in ConfigGenErrorCode.values) {
      final error = ConfigGenException(code, 'detail');
      expect(error.message, matches(RegExp('[а-я]')), reason: code.name);
      expect(error.toString(), endsWith('(detail)'));
    }
    expect(
      const ConfigGenException(ConfigGenErrorCode.empty).toString(),
      isNot(contains('(')),
    );
  });
}
