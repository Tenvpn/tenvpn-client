import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/common/window.dart';
import 'package:fl_clash/common/profile_auto_updater.dart';
import 'package:fl_clash/bootstrap.dart';
import 'package:fl_clash/common/system_dns.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/manager/hotkey_manager.dart';
import 'package:fl_clash/manager/manager.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/tenvpn/tenvpn.dart';
import 'package:fl_clash/views/tenvpn/home.dart';
import 'package:fl_clash/views/tenvpn/theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Widget buildManagerStack({
  required bool isDesktop,
  required bool isAndroid,
  required Future<void> Function(List<ConnectivityResult> results)
  onConnectivityChanged,
  required Widget child,
}) {
  final platformApp = switch ((isDesktop, isAndroid)) {
    (true, _) => WindowHeaderContainer(child: child),
    (false, true) => VpnManager(child: child),
    _ => child,
  };
  final state = AppStateManager(
    child: CoreManager(
      child: ConnectivityManager(
        onConnectivityChanged: onConnectivityChanged,
        child: platformApp,
      ),
    ),
  );
  final platformState = isDesktop
      ? WindowManager(
          child: TrayManager(
            child: HotKeyManager(child: ProxyManager(child: state)),
          ),
        )
      : MobileManager(child: TileManager(child: state));
  return AppEnvManager(
    child: LocaleManager(
      child: StatusManager(
        child: ThemeManager(child: BackManager(child: platformState)),
      ),
    ),
  );
}

const _tooltipTheme = TooltipThemeData(
  waitDuration: Duration(milliseconds: 500),
);

PageTransitionsTheme buildPageTransitionsTheme({
  required bool predictiveBack,
  required bool isMobile,
}) {
  final pageTransitions = isMobile
      ? commonSharedXPageTransitions
      : commonDesktopFadePageTransitions;
  return PageTransitionsTheme(
    builders: <TargetPlatform, PageTransitionsBuilder>{
      TargetPlatform.android: predictiveBack
          ? const PredictiveBackPageTransitionsBuilder()
          : pageTransitions,
      TargetPlatform.windows: pageTransitions,
      TargetPlatform.linux: pageTransitions,
      TargetPlatform.macOS: pageTransitions,
      TargetPlatform.iOS:
          const PageTransitionsTheme().builders[TargetPlatform.iOS]!,
    },
  );
}

class Application extends ConsumerStatefulWidget {
  const Application({super.key});

  @override
  ConsumerState<Application> createState() => ApplicationState();
}

class ApplicationState extends ConsumerState<Application> {
  late final ProfileAutoUpdater _profileAutoUpdater;
  bool _preHasVpn = false;

  @override
  void initState() {
    super.initState();
    _profileAutoUpdater = ProfileAutoUpdater(
      profiles: () => ref.read(profilesProvider),
      update: (profile) =>
          ref.read(profilesActionProvider.notifier).updateProfile(profile),
      onError: (error) => commonPrint.log(compactError(error)),
      refreshOnStart: true,
    );
    ref.listenManual(
      profilesProvider,
      (_, _) => _profileAutoUpdater.reschedule(),
    );
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) async {
      if (globalState.navigatorKey.currentContext != null) {
        await bootstrap.attach();
      } else {
        exit(0);
      }
      if (!mounted) return;
      _profileAutoUpdater.start();
      globalState.isBackground.addListener(_checkProfilesOnResume);
      _initLink();
      unawaited(app?.initShortcuts());
    });
  }

  void _initLink() {
    linkManager.initAppLinksListen(
      (url) => _confirmInstallConfig(url),
      installTenvpnCallBack: (url, awgUrl, awgToken) => _confirmInstallConfig(
        url,
        awg: AwgSource(url: awgUrl, token: awgToken),
      ),
    );
  }

  Future<void> _confirmInstallConfig(String url, {AwgSource? awg}) async {
    unawaited(window?.show());
    final l = currentAppLocalizations;
    final host = Uri.tryParse(url)?.host ?? '';
    final res = await dialogs.showMessage(
      title: l.tenvpnImportTitle,
      message: TextSpan(text: l.tenvpnImportText(host.isEmpty ? url : host)),
    );
    if (res != true) return;
    globalState.navigatorKey.currentState?.popUntil((route) => route.isFirst);
    final error = await ref
        .read(profilesActionProvider.notifier)
        .importSubscription(url, awg: awg, replace: true);
    if (error != null) {
      unawaited(
        dialogs.showMessage(
          title: l.addProfile,
          message: TextSpan(text: error),
        ),
      );
    }
  }

  void _checkProfilesOnResume() {
    if (!globalState.isBackground.value) {
      unawaited(_profileAutoUpdater.check());
    }
  }

  Future<void> _handleConnectivityChanged(
    List<ConnectivityResult> results,
  ) async {
    commonPrint.log('connectivityChanged ${results.toString()}');
    unawaited(systemDnsCoordinator?.resync() ?? Future.value());
    unawaited(ref.read(systemActionProvider.notifier).updateLocalIp());
    final hasVpn = results.contains(ConnectivityResult.vpn);
    final isStart = ref.read(isStartProvider);
    if (_preHasVpn == hasVpn && !isStart) {
      ref.read(checkIpNumProvider.notifier).add();
    }
    _preHasVpn = hasVpn;
  }

  @override
  Widget build(context) {
    return Consumer(
      builder: (_, ref, child) {
        final locale = ref.watch(
          appSettingProvider.select((state) => state.locale),
        );
        final themeProps = ref.watch(themeSettingProvider);
        final supportsPredictiveBack = system.supportsPredictiveBack(
          ref.watch(versionProvider),
        );
        final pageTransitionsTheme = buildPageTransitionsTheme(
          predictiveBack: supportsPredictiveBack && themeProps.predictiveBack,
          isMobile: ref.watch(isMobileViewProvider),
        );
        return ValueListenableBuilder<bool>(
          valueListenable: globalState.isBackground,
          builder: (_, isBackground, _) {
            return TickerMode(
              enabled: !isBackground,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                navigatorKey: globalState.navigatorKey,
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  ...GlobalMaterialLocalizations.delegates,
                ],
                builder: (context, child) {
                  // ignore: deprecated_member_use
                  return MaterialUiCompatibilityBridge(
                    child: IconTheme(
                      data: Theme.of(context).iconTheme,
                      child: buildManagerStack(
                        isDesktop: system.isDesktop,
                        isAndroid: system.isAndroid,
                        onConnectivityChanged: _handleConnectivityChanged,
                        child: child!,
                      ),
                    ),
                  );
                },
                scrollBehavior: const BaseScrollBehavior(),
                title: appName,
                locale: getLocaleForString(locale) ?? appDefaultLocale,
                supportedLocales: AppLocalizations.delegate.supportedLocales,
                themeMode: themeProps.themeMode,
                theme: buildTenvpnTheme(
                  brightness: Brightness.light,
                  pageTransitionsTheme: pageTransitionsTheme,
                  tooltipTheme: _tooltipTheme,
                ),
                darkTheme: buildTenvpnTheme(
                  brightness: Brightness.dark,
                  pageTransitionsTheme: pageTransitionsTheme,
                  tooltipTheme: _tooltipTheme,
                ),
                home: child!,
              ),
            );
          },
        );
      },
      child: const TenvpnHome(),
    );
  }

  @override
  void dispose() {
    linkManager.destroy();
    globalState.isBackground.removeListener(_checkProfilesOnResume);
    _profileAutoUpdater.dispose();
    super.dispose();
  }
}
