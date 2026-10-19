import 'configgen/constants.dart';

enum NetworkMode { open, whitelist, offline }

/// Probed via the core's DIRECT outbound: a whitelist passes these, cuts abroad.
const whitelistProbeUrls = ['https://ya.ru', 'https://www.gosuslugi.ru'];
const openProbeUrls = [
  'https://www.gstatic.com/generate_204',
  'http://www.msftconnecttest.com/connecttest.txt',
];
const networkProbeTimeout = Duration(milliseconds: 2500);

typedef DirectProbe = Future<bool> Function(String url, Duration timeout);

NetworkMode classifyNetwork({
  required bool whitelistReachable,
  required bool openReachable,
}) {
  if (openReachable) return NetworkMode.open;
  return whitelistReachable ? NetworkMode.whitelist : NetworkMode.offline;
}

Future<NetworkMode> detectNetworkMode(DirectProbe probe) async {
  Future<bool> anyReachable(List<String> urls) async {
    final results = await Future.wait([
      for (final url in urls)
        probe(url, networkProbeTimeout).catchError((Object _) => false),
    ]);
    return results.contains(true);
  }

  final [whitelist, open] = await Future.wait([
    anyReachable(whitelistProbeUrls),
    anyReachable(openProbeUrls),
  ]);
  return classifyNetwork(whitelistReachable: whitelist, openReachable: open);
}

/// `''` hands «Авто» back to its tier order, `null` leaves it alone.
String? autoPinFor(NetworkMode mode, {required bool hasWhitelistTier}) =>
    switch (mode) {
      NetworkMode.whitelist => hasWhitelistTier ? autoWhitelistGroupName : null,
      NetworkMode.open => '',
      NetworkMode.offline => null,
    };

typedef PinAuto = Future<void> Function(String tier, {required bool changed});

class NetworkModeController {
  final DirectProbe probe;
  final PinAuto pin;
  final bool Function() hasWhitelistTier;
  NetworkMode? mode;
  String? _pinned;
  int _generation = 0;

  NetworkModeController({
    required this.probe,
    required this.pin,
    required this.hasWhitelistTier,
  });

  Future<NetworkMode?> refresh() async {
    final generation = ++_generation;
    final detected = await detectNetworkMode(probe);
    if (generation != _generation) return null;
    mode = detected;
    final target = autoPinFor(detected, hasWhitelistTier: hasWhitelistTier());
    if (target != null) {
      await pin(target, changed: target != (_pinned ?? ''));
      _pinned = target;
    }
    return detected;
  }

  void reset() {
    _generation++;
    _pinned = null;
    mode = null;
  }
}
