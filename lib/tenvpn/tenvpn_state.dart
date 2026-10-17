import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart';

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

class TenvpnProfileState {
  final AwgSource? awgSource;
  final AwgCache? awgCache;
  final List<ServerEntry> servers;

  const TenvpnProfileState({
    this.awgSource,
    this.awgCache,
    this.servers = const [],
  });

  TenvpnProfileState copyWith({
    AwgSource? Function()? awgSource,
    AwgCache? Function()? awgCache,
    List<ServerEntry>? servers,
  }) => TenvpnProfileState(
    awgSource: awgSource == null ? this.awgSource : awgSource(),
    awgCache: awgCache == null ? this.awgCache : awgCache(),
    servers: servers ?? this.servers,
  );

  factory TenvpnProfileState.fromJson(Map<String, dynamic> json) {
    final source = json['awg_source'];
    final cache = json['awg_cache'];
    final servers = json['servers'];
    return TenvpnProfileState(
      awgSource: source is Map<String, dynamic>
          ? AwgSource.fromJson(source)
          : null,
      awgCache: cache is Map<String, dynamic> ? AwgCache.fromJson(cache) : null,
      servers: servers is List
          ? [
              for (final item in servers.cast<Map<String, dynamic>>())
                ServerEntry(
                  name: item['name'] as String,
                  type: item['type'] as String,
                  network: item['network'] as String?,
                  section: item['section'] as String?,
                ),
            ]
          : const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'awg_source': ?awgSource?.toJson(),
    'awg_cache': ?awgCache?.toJson(),
    'servers': [
      for (final server in servers)
        {
          'name': server.name,
          'type': server.type,
          'network': ?server.network,
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

  Future<void> delete(int profileId) async {
    final file = await _file(profileId);
    if (await file.exists()) await file.delete();
  }
}
