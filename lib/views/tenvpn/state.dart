import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/tenvpn/tenvpn.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// True for [connectingAnimation] after the tunnel goes from off to on.
class TenvpnJustStarted extends Notifier<bool> {
  Timer? _timer;

  @override
  bool build() {
    ref.onDispose(() => _timer?.cancel());
    ref.listen(isStartProvider, (prev, next) {
      _timer?.cancel();
      if (prev == false && next) {
        state = true;
        _timer = Timer(connectingAnimation, () => state = false);
      } else {
        state = false;
      }
    });
    return false;
  }
}

final tenvpnJustStartedProvider = NotifierProvider<TenvpnJustStarted, bool>(
  TenvpnJustStarted.new,
);

/// Until the next check clears it, the IP held was measured before the
/// switch — «Ваш IP: Россия» right after turning the VPN on.
class TenvpnStaleIp extends Notifier<bool> {
  @override
  bool build() {
    ref.listen(isStartProvider, (prev, next) {
      if (prev != next) {
        state = ref.read(networkDetectionProvider).ipInfo != null;
      }
    });
    ref.listen(networkDetectionProvider.select((d) => d.ipInfo == null), (
      _,
      cleared,
    ) {
      if (cleared) state = false;
    });
    return false;
  }
}

final tenvpnStaleIpProvider = NotifierProvider<TenvpnStaleIp, bool>(
  TenvpnStaleIp.new,
);

final tenvpnIpProvider = Provider<IpInfo?>((ref) {
  if (ref.watch(tenvpnStaleIpProvider)) return null;
  return ref.watch(networkDetectionProvider).ipInfo;
});

final tenvpnPhaseProvider = Provider<ConnectionPhase>((ref) {
  final isStart = ref.watch(isStartProvider);
  final detection = ref.watch(networkDetectionProvider);
  final stale = ref.watch(tenvpnStaleIpProvider);
  return connectionPhase(
    isStart: isStart,
    checkingIp: detection.isLoading || stale,
    hasIp: ref.watch(tenvpnIpProvider) != null,
    justStarted: ref.watch(tenvpnJustStartedProvider),
  );
});

typedef TenvpnSelection = ({bool auto, String? server});

final tenvpnSelectionProvider = Provider<TenvpnSelection>((ref) {
  final groups = ref.watch(groupsProvider);
  final main = groups.getGroup(mainGroupName);
  final auto = main == null || main.now != manualGroupName;
  final group = groups.getGroup(auto ? autoGroupName : manualGroupName);
  var server = group?.now;
  while (autoTierGroupNames.contains(server)) {
    server = groups.getGroup(server!)?.now;
  }
  return (auto: auto, server: server?.isEmpty == true ? null : server);
});

final tenvpnServerEntriesProvider = FutureProvider<List<ServerEntry>>((
  ref,
) async {
  final profile = ref.watch(
    currentProfileProvider.select(
      (profile) =>
          profile == null ? null : (profile.id, profile.lastUpdateDate),
    ),
  );
  if (profile == null) return const [];
  return tenvpnConfig.servers(profile.$1);
});

final tenvpnSectionsProvider = Provider<List<ServerSection>>((ref) {
  final manual = ref.watch(groupsProvider).getGroup(manualGroupName);
  final entries = ref.watch(tenvpnServerEntriesProvider).value ?? const [];
  if (manual == null) return const [];
  return groupServers(
    [for (final proxy in manual.all) (name: proxy.name, type: proxy.type)],
    entries,
    awgFirst: ref.watch(tenvpnDesktopAwgProvider),
  );
});

/// On Windows AmneziaWG is the protocol people come for: it gets its own
/// section on top, named after itself rather than «Запасное подключение».
final tenvpnDesktopAwgProvider = Provider<bool>((ref) => system.isWindows);

final tenvpnHasAwgProvider = Provider<bool>((ref) {
  final sections = ref.watch(tenvpnSectionsProvider);
  return sections.any((section) => section.kind == ServerSectionKind.reserve);
});

final tenvpnConfigProvider = Provider<TenvpnConfigService>(
  (ref) => tenvpnConfig,
);

class TenvpnAccountRefresh extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final tenvpnAwgKeyRefreshProvider = NotifierProvider<TenvpnAccountRefresh, int>(
  TenvpnAccountRefresh.new,
);

final tenvpnManualAwgProvider = FutureProvider<bool>((ref) async {
  final id = ref.watch(currentProfileIdProvider);
  ref.watch(tenvpnAwgKeyRefreshProvider);
  if (id == null) return false;
  return ref.read(tenvpnConfigProvider).hasManualAwg(id);
});

final tenvpnAccountRefreshProvider =
    NotifierProvider<TenvpnAccountRefresh, int>(TenvpnAccountRefresh.new);

final tenvpnAccountProvider = FutureProvider<AccountCache?>((ref) async {
  final profile = ref.watch(
    currentProfileProvider.select(
      (profile) =>
          profile == null ? null : (profile.id, profile.lastUpdateDate),
    ),
  );
  ref.watch(tenvpnAccountRefreshProvider);
  if (profile == null) return null;
  return ref.read(tenvpnConfigProvider).account(profile.$1);
});

final tenvpnExpiryProvider = Provider<TenvpnExpiry>((ref) {
  final expire = ref.watch(
    currentProfileProvider.select(
      (profile) => profile?.subscriptionInfo?.expire ?? 0,
    ),
  );
  return resolveExpiry(
    account: ref.watch(tenvpnAccountProvider).value,
    subscription: expiryFromHeader(expire),
  );
});

final tenvpnRenewUrlProvider = Provider<String>((ref) {
  final expiry = ref.watch(tenvpnExpiryProvider);
  return expiry.account?.renewUrl ?? tenvpnBotUrl;
});
