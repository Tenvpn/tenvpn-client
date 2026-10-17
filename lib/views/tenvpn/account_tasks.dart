import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/tenvpn/tenvpn.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import 'state.dart';

typedef ShowAccountNotice =
    Future<bool> Function({
      required String channelName,
      required String title,
      required String text,
    });

typedef SendConnectEvent =
    Future<bool> Function(String token, ConnectEvent event);

final showAccountNoticeProvider = Provider<ShowAccountNotice?>(
  (ref) => app?.showAccountNotice,
);

final sendConnectEventProvider = Provider<SendConnectEvent?>((ref) {
  final endpoints = TenvpnEndpoints.configured;
  if (endpoints == null) return null;
  return (token, event) =>
      sendConnectEvent(endpoints, token, event, tenvpnPost);
});

final telemetryThrottleProvider = Provider<TelemetryThrottle>(
  (ref) => TelemetryThrottle(),
);

const accountRefreshAge = Duration(minutes: 10);

/// Account upkeep that has no screen of its own: the 2-day expiry notice,
/// the connect event for support and a fresh balance after the app returns.
class TenvpnAccountTasks extends ConsumerStatefulWidget {
  final Widget child;

  const TenvpnAccountTasks({super.key, required this.child});

  @override
  ConsumerState<TenvpnAccountTasks> createState() => _TenvpnAccountTasksState();
}

class _TenvpnAccountTasksState extends ConsumerState<TenvpnAccountTasks> {
  late final AppLifecycleListener _lifecycle;

  String? _noticeChecking;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refreshIfStale);
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshIfStale());
    ref.listenManual(
      tenvpnExpiryProvider,
      (_, next) => unawaited(_checkNotice(next)),
      fireImmediately: true,
    );
    ref.listenManual(tenvpnPhaseProvider, (prev, next) {
      if (prev != ConnectionPhase.on && next == ConnectionPhase.on) {
        unawaited(_reportConnect());
      }
    });
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  int? get _profileId => ref.read(currentProfileIdProvider);

  TenvpnConfigService get _config => ref.read(tenvpnConfigProvider);

  Future<void> _refreshIfStale() async {
    final id = _profileId;
    if (id == null) return;
    final cached = await _config.account(id);
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) < accountRefreshAge) {
      return;
    }
    if (await _config.appToken(id) == null) return;
    await _config.refreshAccount(id);
    if (mounted) ref.read(tenvpnAccountRefreshProvider.notifier).bump();
  }

  Future<void> _checkNotice(TenvpnExpiry expiry) async {
    final show = ref.read(showAccountNoticeProvider);
    final id = _profileId;
    if (show == null || id == null) return;
    final key = expiryNoticeKey(
      expiry,
      DateTime.now(),
      alreadyShown: await _config.expiryNoticeFor(id),
    );
    if (key == null || !mounted || _noticeChecking == key) return;
    _noticeChecking = key;
    final l = currentAppLocalizations;
    final locale = Localizations.maybeLocaleOf(context)?.toLanguageTag();
    final date = DateFormat.MMMMd(locale).format(expiry.date!);
    final shown = await show(
      channelName: l.tenvpnNoticeChannel,
      title: l.tenvpnExpiryNoticeTitle,
      text: l.tenvpnExpiryNoticeText(date),
    );
    if (shown) {
      await _config.markExpiryNotice(id, key);
    } else {
      _noticeChecking = null;
    }
  }

  Future<void> _reportConnect() async {
    if (!ref.read(appSettingProvider).tenvpnTelemetry) return;
    final send = ref.read(sendConnectEventProvider);
    final id = _profileId;
    if (send == null || id == null) return;
    final token = await _config.appToken(id);
    if (token == null) return;
    final server = ref.read(tenvpnSelectionProvider).server;
    final List<ServerEntry> entries;
    try {
      entries = await ref.read(tenvpnServerEntriesProvider.future);
    } catch (_) {
      return;
    }
    if (!mounted) return;
    final protocol = connectionProtocol(
      entries.where((entry) => entry.name == server).firstOrNull,
    );
    if (!ref.read(telemetryThrottleProvider).allow(protocol)) return;
    await send(
      token,
      ConnectEvent(
        appVersion: globalState.packageInfo.version,
        platform: system.isAndroid
            ? 'android'
            : system.isWindows
            ? 'windows'
            : system.isIOS
            ? 'ios'
            : 'other',
        osVersion: '${ref.read(versionProvider)}',
        protocol: protocol,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
