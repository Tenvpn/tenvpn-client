import 'dart:math';

import 'constants.dart';
import 'subscription.dart';

enum AutoStrategy {
  fastest,

  /// AmneziaWG first, the rest of the pool only when it is down: the
  /// Windows "AWG priority" mode planned for session 3.
  awgFirst,
}

class ConfigGenOptions {
  final String testUrl;
  final int testIntervalSeconds;
  final int toleranceMs;
  final bool tun;
  final String controllerAddress;
  final String? controllerSecret;
  final int mixedPort;
  final AutoStrategy autoStrategy;

  const ConfigGenOptions({
    this.testUrl = 'https://www.gstatic.com/generate_204',
    this.testIntervalSeconds = 300,
    this.toleranceMs = 50,
    this.tun = true,
    this.controllerAddress = '127.0.0.1:9090',
    this.controllerSecret,
    this.mixedPort = 7890,
    this.autoStrategy = AutoStrategy.fastest,
  });
}

// Bootstrap and proxy-server lookups must work on networks that only let
// Russian resources through, so Yandex DNS goes first; nothing Chinese.
const tenvpnDefaultNameservers = ['77.88.8.8', '1.1.1.1'];
const tenvpnNameservers = ['https://1.1.1.1/dns-query', '77.88.8.8'];
const tenvpnProxyServerNameservers = ['77.88.8.8', '77.88.8.1', '1.1.1.1'];
const tenvpnFakeIpFilter = [
  '*.lan',
  '+.local',
  '+.home.arpa',
  'localhost',
  '+.msftconnecttest.com',
  '+.msftncsi.com',
  '+.pool.ntp.org',
  'time.*.com',
  'time.*.gov',
  'time.*.apple.com',
  'ntp.*.com',
  'stun.*.*',
  'stun.*.*.*',
  '+.stun.*.*',
  '+.stun.*.*.*',
];
const privateNetworkRules = [
  'IP-CIDR,127.0.0.0/8,DIRECT,no-resolve',
  'IP-CIDR,10.0.0.0/8,DIRECT,no-resolve',
  'IP-CIDR,172.16.0.0/12,DIRECT,no-resolve',
  'IP-CIDR,192.168.0.0/16,DIRECT,no-resolve',
  'IP-CIDR,169.254.0.0/16,DIRECT,no-resolve',
  'IP-CIDR,100.64.0.0/10,DIRECT,no-resolve',
  'IP-CIDR6,::1/128,DIRECT,no-resolve',
  'IP-CIDR6,fc00::/7,DIRECT,no-resolve',
  'IP-CIDR6,fe80::/10,DIRECT,no-resolve',
];

class GeneratedConfig {
  final Map<String, dynamic> config;
  final List<ServerEntry> servers;
  final String secret;

  const GeneratedConfig({
    required this.config,
    required this.servers,
    required this.secret,
  });
}

GeneratedConfig buildConfig(
  ParsedSubscription subscription, {
  Map<String, dynamic>? awg,
  ConfigGenOptions options = const ConfigGenOptions(),
  Random? random,
}) {
  final proxies = [
    for (final proxy in subscription.proxies) Map<String, dynamic>.from(proxy),
  ];
  final servers = [...subscription.servers];
  final awgNames = <String>[];
  if (awg != null) {
    final used = proxies.map((proxy) => proxy['name'] as String).toSet();
    final name = uniqueName(
      awg['name'] as String,
      used,
      reserved: reservedProxyNames,
    );
    proxies.add({...awg, 'name': name});
    awgNames.add(name);
    servers.add(
      ServerEntry(name: name, type: 'wireguard', section: awgSectionTitle),
    );
  }
  final allNames = proxies.map((proxy) => proxy['name'] as String).toList();
  final poolNames = allNames.where((name) => !awgNames.contains(name)).toList();
  final secret = options.controllerSecret ?? generateSecret(random);
  final groups = <Map<String, dynamic>>[
    {
      'name': mainGroupName,
      'type': 'select',
      'proxies': [autoGroupName, manualGroupName],
    },
  ];
  final useAwgFirst =
      options.autoStrategy == AutoStrategy.awgFirst &&
      awgNames.isNotEmpty &&
      poolNames.isNotEmpty;
  if (useAwgFirst) {
    groups.add({
      'name': autoGroupName,
      'type': 'fallback',
      'proxies': [...awgNames, autoPoolGroupName],
      ..._healthCheck(options),
    });
    groups.add({
      'name': autoPoolGroupName,
      'type': 'url-test',
      'proxies': poolNames,
      'tolerance': options.toleranceMs,
      'hidden': true,
      ..._healthCheck(options),
    });
  } else {
    groups.add({
      'name': autoGroupName,
      'type': 'url-test',
      'proxies': allNames,
      'tolerance': options.toleranceMs,
      ..._healthCheck(options),
    });
  }
  groups.add({'name': manualGroupName, 'type': 'select', 'proxies': allNames});
  final config = <String, dynamic>{
    'mixed-port': options.mixedPort,
    'allow-lan': false,
    'mode': 'rule',
    'log-level': 'warning',
    'ipv6': false,
    'unified-delay': true,
    'tcp-concurrent': true,
    'external-controller': options.controllerAddress,
    'secret': secret,
    'profile': {'store-selected': true},
    'tun': {
      'enable': options.tun,
      'stack': 'mixed',
      'auto-route': true,
      'auto-detect-interface': true,
      'dns-hijack': ['any:53'],
    },
    'dns': {
      'enable': true,
      'listen': '0.0.0.0:1053',
      'ipv6': false,
      'enhanced-mode': 'fake-ip',
      'fake-ip-range': '198.18.0.1/16',
      'fake-ip-filter': tenvpnFakeIpFilter,
      'default-nameserver': tenvpnDefaultNameservers,
      'nameserver': tenvpnNameservers,
      'proxy-server-nameserver': tenvpnProxyServerNameservers,
    },
    'proxies': proxies,
    'proxy-groups': groups,
    'rules': [...privateNetworkRules, 'MATCH,$mainGroupName'],
  };
  return GeneratedConfig(config: config, servers: servers, secret: secret);
}

Map<String, dynamic> _healthCheck(ConfigGenOptions options) => {
  'url': options.testUrl,
  'interval': options.testIntervalSeconds,
};

String generateSecret([Random? random]) {
  final source = random ?? Random.secure();
  return List.generate(32, (_) => source.nextInt(16).toRadixString(16)).join();
}
