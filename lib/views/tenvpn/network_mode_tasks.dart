import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/tenvpn/tenvpn.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const _settleDelay = Duration(milliseconds: 1500);
const _offlineRetries = 3;
const _offlineRetryDelay = Duration(seconds: 3);
const _reviveTimeout = Duration(seconds: 5);
const _recheckGap = Duration(seconds: 30);

/// Pins «Авто» to the whitelist tier the moment a direct probe sees one,
/// on connect and on every network change while the app is alive.
class TenvpnNetworkModeTasks extends ConsumerStatefulWidget {
  final Widget child;
  final Stream<List<ConnectivityResult>>? connectivity;
  final NetworkModeController? controller;

  const TenvpnNetworkModeTasks({
    super.key,
    required this.child,
    this.connectivity,
    this.controller,
  });

  @override
  ConsumerState<TenvpnNetworkModeTasks> createState() =>
      _TenvpnNetworkModeTasksState();
}

class _TenvpnNetworkModeTasksState
    extends ConsumerState<TenvpnNetworkModeTasks> {
  late final NetworkModeController _controller =
      widget.controller ??
      NetworkModeController(
        probe: (url, timeout) async {
          final delay = await ref
              .read(coreHandlerProvider)
              .getDelay(url, 'DIRECT', timeout: timeout);
          return (delay?.value ?? -1) >= 0;
        },
        pin: (tier, {required changed}) async {
          await ref
              .read(coreHandlerProvider)
              .changeProxy(
                ChangeProxyParams(groupName: autoGroupName, proxyName: tier),
                closeConnections: changed,
              );
          await ref.read(proxiesActionProvider.notifier).updateGroups();
        },
        hasWhitelistTier: () =>
            ref.read(groupsProvider).getGroup(autoWhitelistGroupName) != null,
        // A fresh delay test on the fallback's own URL marks the regular tier
        // alive again, so «Авто» leaves CDN without waiting for its interval.
        revivePrimary: () async {
          final groups = ref.read(groupsProvider);
          if (groups.getGroup(autoPrimaryGroupName) == null) return;
          await ref
              .read(coreHandlerProvider)
              .getDelay(
                groups.getGroup(autoGroupName)?.testUrl ??
                    const ConfigGenOptions().testUrl,
                autoPrimaryGroupName,
                timeout: _reviveTimeout,
              );
        },
      );
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _timer;
  DateTime? _lastRefresh;

  @override
  void initState() {
    super.initState();
    _subscription =
        (widget.connectivity ?? Connectivity().onConnectivityChanged).listen(
          (_) => _schedule(_settleDelay),
        );
    ref.listenManual(isStartProvider, (previous, next) {
      if (next && previous != true) {
        _schedule(_settleDelay);
      } else if (!next) {
        _timer?.cancel();
        _controller.reset();
      }
    }, fireImmediately: true);
    ref.listenManual(
      groupsProvider.select((groups) => groups.getGroup(autoGroupName)?.now),
      (_, now) {
        final last = _lastRefresh;
        if (now == autoWhitelistGroupName &&
            _controller.mode != NetworkMode.whitelist &&
            ref.read(isStartProvider) &&
            (last == null || DateTime.now().difference(last) > _recheckGap)) {
          _schedule(_settleDelay);
        }
      },
    );
  }

  void _schedule(Duration delay, [int attempt = 0]) {
    _timer?.cancel();
    _timer = Timer(delay, () => unawaited(_refresh(attempt)));
  }

  Future<void> _refresh(int attempt) async {
    if (!mounted || !ref.read(isStartProvider)) return;
    _lastRefresh = DateTime.now();
    final mode = await _controller.refresh();
    if (!mounted || mode == null) return;
    commonPrint.log('TENVPN network: ${mode.name}', logLevel: LogLevel.info);
    if (mode == NetworkMode.offline && attempt < _offlineRetries) {
      _schedule(_offlineRetryDelay, attempt + 1);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
