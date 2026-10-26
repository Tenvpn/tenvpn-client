import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart';

import 'account.dart';
import 'awg_source.dart';
import 'configgen/subscription.dart';

class AwgCache {
  final String conf;
  final String? name;
  final DateTime fetchedAt;

  const AwgCache({required this.conf, this.name, required this.fetchedAt});

  factory AwgCache.fromJson(Map<String, dynamic> json) => AwgCache(
    conf: json['conf'] as String,
    name: json['name'] as String?,
    fetchedAt: DateTime.parse(json['fetched_at'] as String),
  );

  Map<String, dynamic> toJson() => {
    'conf': conf,
    'name': ?name,
    'fetched_at': fetchedAt.toUtc().toIso8601String(),
  };
}

class AccountCache {
  final AccountInfo account;
  final DateTime fetchedAt;

  const AccountCache({required this.account, required this.fetchedAt});

  factory AccountCache.fromJson(Map<String, dynamic> json) => AccountCache(
    account: AccountInfo.fromJson(json['account'] as Map<String, dynamic>),
    fetchedAt: DateTime.parse(json['fetched_at'] as String),
  );

  Map<String, dynamic> toJson() => {
    'account': account.toJson(),
    'fetched_at': fetchedAt.toUtc().toIso8601String(),
  };

  DateTime get expiry => account.expiry(fetchedAt.toLocal());
}

class TenvpnProfileState {
  final AwgSource? awgSource;
  final AwgCache? awgCache;
  final String? awgManual;
  final String? appToken;
  final AccountCache? account;
  final String? expiryNoticeFor;
  final List<ServerEntry> servers;

  const TenvpnProfileState({
    this.awgSource,
    this.awgCache,
    this.awgManual,
    this.appToken,
    this.account,
    this.expiryNoticeFor,
    this.servers = const [],
  });

  TenvpnProfileState copyWith({
    AwgSource? Function()? awgSource,
    AwgCache? Function()? awgCache,
    String? Function()? awgManual,
    String? Function()? appToken,
    AccountCache? Function()? account,
    String? Function()? expiryNoticeFor,
    List<ServerEntry>? servers,
  }) => TenvpnProfileState(
    awgSource: awgSource == null ? this.awgSource : awgSource(),
    awgCache: awgCache == null ? this.awgCache : awgCache(),
    awgManual: awgManual == null ? this.awgManual : awgManual(),
    appToken: appToken == null ? this.appToken : appToken(),
    account: account == null ? this.account : account(),
    expiryNoticeFor: expiryNoticeFor == null
        ? this.expiryNoticeFor
        : expiryNoticeFor(),
    servers: servers ?? this.servers,
  );

  factory TenvpnProfileState.fromJson(Map<String, dynamic> json) {
    final source = json['awg_source'];
    final cache = json['awg_cache'];
    final manual = json['awg_manual'];
    final token = json['app_token'];
    final account = json['account'];
    final notice = json['expiry_notice_for'];
    final servers = json['servers'];
    AccountCache? accountCache;
    if (account is Map<String, dynamic>) {
      try {
        accountCache = AccountCache.fromJson(account);
      } on Object {
        accountCache = null;
      }
    }
    return TenvpnProfileState(
      awgSource: source is Map<String, dynamic>
          ? AwgSource.fromJson(source)
          : null,
      awgCache: cache is Map<String, dynamic> ? AwgCache.fromJson(cache) : null,
      awgManual: manual is String && manual.isNotEmpty ? manual : null,
      appToken: token is String && token.isNotEmpty ? token : null,
      account: accountCache,
      expiryNoticeFor: notice is String ? notice : null,
      servers: servers is List
          ? [
              for (final item in servers.cast<Map<String, dynamic>>())
                ServerEntry(
                  name: item['name'] as String,
                  type: item['type'] as String,
                  network: item['network'] as String?,
                  security: item['security'] as String?,
                  section: item['section'] as String?,
                ),
            ]
          : const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'awg_source': ?awgSource?.toJson(),
    'awg_cache': ?awgCache?.toJson(),
    'awg_manual': ?awgManual,
    'app_token': ?appToken,
    'account': ?account?.toJson(),
    'expiry_notice_for': ?expiryNoticeFor,
    'servers': [
      for (final server in servers)
        {
          'name': server.name,
          'type': server.type,
          'network': ?server.network,
          'security': ?server.security,
          'section': ?server.section,
        },
    ],
  };
}

/// One JSON file per profile, kept outside the profiles directory: the
/// orphan sweep there deletes every file whose name is not a bare profile id.
class TenvpnStateStore {
  final Future<String> Function() directory;

  const TenvpnStateStore(this.directory);

  Future<File> _file(int profileId) async =>
      File(join(await directory(), '$profileId.json'));

  Future<TenvpnProfileState> load(int profileId) async {
    final file = await _file(profileId);
    if (!await file.exists()) return const TenvpnProfileState();
    try {
      final data = json.decode(await file.readAsString());
      if (data is Map<String, dynamic>) {
        return TenvpnProfileState.fromJson(data);
      }
    } on FormatException {
      // A torn write only costs the AWG cache; the next update rewrites it.
    }
    return const TenvpnProfileState();
  }

  Future<void> save(int profileId, TenvpnProfileState state) async {
    final file = await _file(profileId);
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(json.encode(state.toJson()), flush: true);
    await temp.rename(file.path);
  }

  Future<File> _subscriptionFile(int profileId) async =>
      File(join(await directory(), '$profileId.subscription.yaml'));

  /// The last download, so a settings change rebuilds without the network.
  Future<String?> loadSubscription(int profileId) async {
    final file = await _subscriptionFile(profileId);
    return await file.exists() ? file.readAsString() : null;
  }

  Future<void> saveSubscription(int profileId, String subscription) async {
    final file = await _subscriptionFile(profileId);
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(subscription, flush: true);
    await temp.rename(file.path);
  }

  Future<void> delete(int profileId) async {
    for (final file in [
      await _file(profileId),
      await _subscriptionFile(profileId),
    ]) {
      if (await file.exists()) await file.delete();
    }
  }
}
