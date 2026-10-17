import 'dart:math';

import 'constants.dart';
import 'subscription.dart';

/// Order of the tiers inside «Авто»: regular servers → AmneziaWG → servers
/// for mobile whitelists (CDN traffic is paid and slower, so it goes last).
enum AutoStrategy { fastest, awgFirst }

class ConfigGenOptions {
  final String testUrl;

  /// The tier switch: mihomo re-tests groups only on a timer or after
  /// [maxFailedTimes] dial failures, never on a network change.
  final int autoIntervalSeconds;
  final int testIntervalSeconds;
  final int whitelistIntervalSeconds;
  final int testTimeoutMs;
  final int whitelistTimeoutMs;
  final int toleranceMs;
  final int whitelistToleranceMs;
  final int maxFailedTimes;
  final bool tun;
  final String controllerAddress;
  final String? controllerSecret;
  final int mixedPort;
  final AutoStrategy autoStrategy;

  const ConfigGenOptions({
    this.testUrl = 'https://www.gstatic.com/generate_204',
    this.autoIntervalSeconds = 15,
    this.testIntervalSeconds = 120,
    this.whitelistIntervalSeconds = 300,
    this.testTimeoutMs = 3000,
    this.whitelistTimeoutMs = 5000,
    this.toleranceMs = 100,
    this.whitelistToleranceMs = 150,
    this.maxFailedTimes = 3,
    this.tun = true,
    this.controllerAddress = '127.0.0.1:9090',
    this.controllerSecret,
    this.mixedPort = 7890,
    this.autoStrategy = AutoStrategy.fastest,
  });
}

const xrayPaddingDefaults = {
  'x-padding-header': 'X-Padding',
  'x-padding-key': 'x_padding',
  'x-padding-placement': 'queryInHeader',
  'x-padding-method': 'repeat-x',
};

/// Xray defaults empty padding fields and (26.9.8+) demands ML-KEM; mihomo doesn't.
Map<String, dynamic> alignWithXray(Map<String, dynamic> proxy) {
  final aligned = Map<String, dynamic>.from(proxy);
  final xhttp = aligned['xhttp-opts'];
  if (xhttp is Map && xhttp['x-padding-obfs-mode'] == true) {
    aligned['xhttp-opts'] = {
      ...xhttp,
      for (final MapEntry(:key, :value) in xrayPaddingDefaults.entries)
        if (xhttp[key] == null || xhttp[key] == '') key: value,
    };
  }
  final reality = aligned['reality-opts'];
  if (reality is Map) {
    aligned['reality-opts'] = {...reality, 'support-x25519mlkem768': true};
    aligned['client-fingerprint'] = 'chrome';
  }
  return aligned;
}

bool isWhitelistServer(ServerEntry server) =>
    whitelistWords.hasMatch(server.name) ||
    (server.section != null && whitelistWords.hasMatch(server.section!));

// Server addresses must resolve directly even where only Russian resources
// are reachable, so Yandex answers those; every other lookup rides the tunnel
// (mihomo queries nameservers in parallel, so order alone keeps nothing out).
const tenvpnDefaultNameservers = ['77.88.8.8', '1.1.1.1'];
const tenvpnNameservers = [
  'https://1.1.1.1/dns-query#$mainGroupName',
  'https://8.8.8.8/dns-query#$mainGroupName',
];
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
    for (final proxy in subscription.proxies) alignWithXray(proxy),
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
      ServerEntry(
        name: name,
        type: 'wireguard',
        security: awg.containsKey('amnezia-wg-option') ? 'amnezia' : null,
        section: awgSectionTitle,
      ),
    );
  }
  final allNames = proxies.map((proxy) => proxy['name'] as String).toList();
  final whitelist = {
    for (final server in servers)
      if (!awgNames.contains(server.name) && isWhitelistServer(server))
        server.name,
  };
  final primaryNames = [
    for (final name in allNames)
      if (!awgNames.contains(name) && !whitelist.contains(name)) name,
  ];
  final whitelistNames = allNames.where(whitelist.contains).toList();
  final secret = options.controllerSecret ?? generateSecret(random);
  final groups = <Map<String, dynamic>>[
    {
      'name': mainGroupName,
      'type': 'select',
      'proxies': [autoGroupName, manualGroupName],
    },
    ..._autoGroups(primaryNames, awgNames, whitelistNames, options),
    {'name': manualGroupName, 'type': 'select', 'proxies': allNames},
  ];
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
      'listen': '127.0.0.1:1053',
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

List<Map<String, dynamic>> _autoGroups(
  List<String> primary,
  List<String> awg,
  List<String> whitelist,
  ConfigGenOptions options,
) {
  Map<String, dynamic> urlTest(String name, List<String> proxies, bool wl) => {
    'name': name,
    'type': 'url-test',
    'proxies': proxies,
    'url': options.testUrl,
    'expected-status': '204',
    'interval': wl
        ? options.whitelistIntervalSeconds
        : options.testIntervalSeconds,
    'timeout': wl ? options.whitelistTimeoutMs : options.testTimeoutMs,
    'tolerance': wl ? options.whitelistToleranceMs : options.toleranceMs,
    'lazy': true,
    if (!wl) 'max-failed-times': options.maxFailedTimes,
  };
  final tiers = [
    if (primary.isNotEmpty) (autoPrimaryGroupName, primary, false),
    if (whitelist.isNotEmpty) (autoWhitelistGroupName, whitelist, true),
  ];
  if (awg.isEmpty && tiers.length < 2) {
    final (_, proxies, wl) = tiers.single;
    return [urlTest(autoGroupName, proxies, wl)];
  }
  final members = [
    if (options.autoStrategy == AutoStrategy.awgFirst) ...awg,
    if (primary.isNotEmpty) autoPrimaryGroupName,
    if (options.autoStrategy == AutoStrategy.fastest) ...awg,
    if (whitelist.isNotEmpty) autoWhitelistGroupName,
  ];
  return [
    {
      'name': autoGroupName,
      'type': 'fallback',
      'proxies': members,
      'url': options.testUrl,
      'expected-status': '204',
      'interval': options.autoIntervalSeconds,
      'timeout': options.testTimeoutMs,
      'lazy': true,
      'max-failed-times': options.maxFailedTimes,
    },
    for (final (name, proxies, wl) in tiers)
      {...urlTest(name, proxies, wl), 'hidden': true},
  ];
}

String generateSecret([Random? random]) {
  final source = random ?? Random.secure();
  return List.generate(32, (_) => source.nextInt(16).toRadixString(16)).join();
}
