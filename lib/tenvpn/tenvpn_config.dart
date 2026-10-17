import 'awg_source.dart';
import 'configgen/configgen.dart';
import 'tenvpn_state.dart';

typedef TenvpnLog = void Function(String message);

class TenvpnConfigService {
  final TenvpnStateStore store;
  final AwgTransport transport;
  final ConfigGenOptions Function() options;
  final DateTime Function() now;
  final TenvpnLog log;

  TenvpnConfigService({
    required this.store,
    required this.transport,
    ConfigGenOptions Function()? options,
    DateTime Function()? now,
    TenvpnLog? log,
  }) : options = options ?? (() => const ConfigGenOptions()),
       now = now ?? DateTime.now,
       log = log ?? ((_) {});

  /// Subscription text in, final mihomo YAML out. Throws
  /// [ConfigGenException] before any network call when the subscription is
  /// unusable, so a broken download never replaces the cached profile.
  Future<String> generate(int profileId, String subscription) async {
    final parsed = parseSubscription(subscription);
    var state = await store.load(profileId);
    state = await _refreshAwg(state);
    final awg = _awgProxy(state);
    final generated = buildConfig(parsed, awg: awg, options: options());
    await store.save(profileId, state.copyWith(servers: generated.servers));
    return encodeConfig(generated);
  }

  Future<void> setAwgSource(int profileId, AwgSource? source) async {
    final state = await store.load(profileId);
    await store.save(
      profileId,
      state.copyWith(awgSource: () => source, awgCache: () => null),
    );
  }

  Future<List<ServerEntry>> servers(int profileId) async =>
      (await store.load(profileId)).servers;

  Future<void> forget(int profileId) => store.delete(profileId);

  Future<TenvpnProfileState> _refreshAwg(TenvpnProfileState state) async {
    final source = state.awgSource;
    if (source == null) return state.copyWith(awgCache: () => null);
    final result = await fetchAwg(source, transport);
    switch (result) {
      case AwgFetched(:final conf, :final name):
        try {
          parseAwgConf(conf);
        } on ConfigGenException catch (e) {
          log('tenvpn awg: ignoring invalid profile: ${e.detail}');
          return state;
        }
        return state.copyWith(
          awgCache: () => AwgCache(conf: conf, name: name, fetchedAt: now()),
        );
      case AwgRevoked(:final statusCode):
        log('tenvpn awg: revoked by backend (HTTP $statusCode)');
        return state.copyWith(awgCache: () => null);
      case AwgUnavailable(:final reason):
        log('tenvpn awg: unavailable ($reason), using cache');
        return state;
    }
  }

  Map<String, dynamic>? _awgProxy(TenvpnProfileState state) {
    final cache = state.awgCache;
    if (cache == null) return null;
    try {
      return parseAwgConf(cache.conf, name: cache.name ?? awgDefaultName);
    } on ConfigGenException catch (e) {
      log('tenvpn awg: cached profile unreadable: ${e.detail}');
      return null;
    }
  }
}
