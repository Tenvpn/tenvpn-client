import 'account.dart';
import 'awg_source.dart';
import 'configgen/configgen.dart';
import 'tenvpn_state.dart';

typedef TenvpnLog = void Function(String message);

class TenvpnConfigService {
  final TenvpnStateStore store;
  final AwgTransport transport;
  final TenvpnEndpoints? endpoints;
  final ConfigGenOptions Function() options;
  final DateTime Function() now;
  final TenvpnLog log;

  TenvpnConfigService({
    required this.store,
    required this.transport,
    this.endpoints,
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
    final loaded = await store.load(profileId);
    final (awgState, account) = await (
      _refreshAwg(loaded),
      _fetchAccount(loaded),
    ).wait;
    final state = _withAccount(awgState, account);
    final awg = _awgProxy(state);
    final generated = buildConfig(parsed, awg: awg, options: options());
    await store.save(profileId, state.copyWith(servers: generated.servers));
    await store.saveSubscription(profileId, subscription);
    return encodeConfig(generated);
  }

  /// Offline rebuild with the current options; `null` when nothing is cached.
  Future<String?> regenerate(int profileId) async {
    final subscription = await store.loadSubscription(profileId);
    if (subscription == null) return null;
    final state = await store.load(profileId);
    final generated = buildConfig(
      subscription.isEmpty
          ? ParsedSubscription.empty
          : parseSubscription(subscription),
      awg: _awgProxy(state),
      options: options(),
    );
    await store.save(profileId, state.copyWith(servers: generated.servers));
    return encodeConfig(generated);
  }

  /// A pasted key beats any server source; a bad one throws unsaved.
  Future<void> setManualAwg(int profileId, String? conf) async {
    if (conf != null) parseAwgConf(conf);
    final state = await store.load(profileId);
    await store.save(profileId, state.copyWith(awgManual: () => conf));
  }

  /// A profile of one AmneziaWG key and no subscription: the cached
  /// subscription is empty, so offline rebuilds keep working.
  Future<String> generateAwgOnly(int profileId, String conf) async {
    await setManualAwg(profileId, conf);
    await store.saveSubscription(profileId, '');
    return (await regenerate(profileId))!;
  }

  Future<bool> hasManualAwg(int profileId) async =>
      (await store.load(profileId)).awgManual != null;

  Future<void> setAwgSource(int profileId, AwgSource? source) async {
    final state = await store.load(profileId);
    await store.save(
      profileId,
      state.copyWith(awgSource: () => source, awgCache: () => null),
    );
  }

  /// The device token from `tenvpn://import`: one secret for AmneziaWG,
  /// the account and telemetry, replacing any `install-config` AWG source.
  Future<void> setAppToken(int profileId, String? token) async {
    final state = await store.load(profileId);
    await store.save(
      profileId,
      state.copyWith(
        appToken: () => token,
        awgSource: () => null,
        awgCache: () => null,
        account: () => null,
      ),
    );
  }

  Future<String?> appToken(int profileId) async =>
      (await store.load(profileId)).appToken;

  Future<AccountCache?> account(int profileId) async =>
      (await store.load(profileId)).account;

  Future<AccountCache?> refreshAccount(int profileId) async {
    final state = await store.load(profileId);
    final result = await _fetchAccount(state);
    if (result == null) return state.account;
    final next = _withAccount(state, result);
    await store.save(profileId, next);
    return next.account;
  }

  Future<String?> expiryNoticeFor(int profileId) async =>
      (await store.load(profileId)).expiryNoticeFor;

  Future<void> markExpiryNotice(int profileId, String key) async {
    final state = await store.load(profileId);
    await store.save(profileId, state.copyWith(expiryNoticeFor: () => key));
  }

  Future<List<ServerEntry>> servers(int profileId) async =>
      (await store.load(profileId)).servers;

  Future<void> forget(int profileId) => store.delete(profileId);

  AwgSource? _awgSourceOf(TenvpnProfileState state) {
    final explicit = state.awgSource;
    if (explicit != null) return explicit;
    final token = state.appToken;
    final api = endpoints;
    if (token == null || api == null) return null;
    return AwgSource(url: api.awg, token: token);
  }

  Future<AccountFetchResult?> _fetchAccount(TenvpnProfileState state) async {
    final token = state.appToken;
    final api = endpoints;
    if (token == null || api == null) return null;
    return fetchAccount(api, token, transport);
  }

  TenvpnProfileState _withAccount(
    TenvpnProfileState state,
    AccountFetchResult? result,
  ) {
    switch (result) {
      case null:
        return state;
      case AccountFetched(:final account):
        return state.copyWith(
          account: () => AccountCache(account: account, fetchedAt: now()),
        );
      case AccountRevoked(:final statusCode):
        log('tenvpn account: token rejected (HTTP $statusCode)');
        return state.copyWith(account: () => null);
      case AccountUnavailable(:final reason):
        log('tenvpn account: unavailable ($reason), using cache');
        return state;
    }
  }

  Future<TenvpnProfileState> _refreshAwg(TenvpnProfileState state) async {
    if (state.awgManual != null) return state;
    final source = _awgSourceOf(state);
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
    final manual = state.awgManual;
    if (manual != null) {
      try {
        return parseAwgConf(manual);
      } on ConfigGenException {
        log('tenvpn awg: pasted key unreadable');
      }
    }
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
