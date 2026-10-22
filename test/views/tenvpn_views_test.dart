import 'dart:io';
import 'dart:math';

import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/tenvpn/tenvpn.dart';
import 'package:fl_clash/views/tenvpn/advanced_view.dart';
import 'package:fl_clash/views/tenvpn/home.dart';
import 'package:fl_clash/views/tenvpn/main_view.dart';
import 'package:fl_clash/views/tenvpn/mascot.dart';
import 'package:fl_clash/views/tenvpn/onboarding_view.dart';
import 'package:fl_clash/views/tenvpn/servers_view.dart';
import 'package:fl_clash/views/tenvpn/settings_view.dart';
import 'package:fl_clash/views/tenvpn/state.dart';
import 'package:fl_clash/views/tenvpn/theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

class _FakeCommonAction extends CommonAction {
  int toggles = 0;

  @override
  void toggleRunning() => toggles++;
}

class _FakeProxiesAction extends ProxiesAction {
  final selected = <String?>[];
  int speedChecks = 0;

  @override
  Future<void> selectTenvpnServer(String? serverName) async {
    selected.add(serverName);
  }

  @override
  Future<void> delayTestGroups(List<Group> groups) async => speedChecks++;
}

class _FakeProfilesAction extends ProfilesAction {
  String? result;
  final imported = <(String, AwgSource?, bool)>[];
  final tokens = <String?>[];

  @override
  Future<String?> importSubscription(
    String url, {
    AwgSource? awg,
    String? token,
    bool replace = false,
  }) async {
    imported.add((url, awg, replace));
    tokens.add(token);
    return result;
  }
}

class _FixedDetection extends NetworkDetection {
  final NetworkDetectionState initial;

  _FixedDetection(this.initial);

  @override
  NetworkDetectionState build() => initial;
}

const _servers = [
  ServerEntry(name: '🇸🇪 ⚡ Швеция', type: 'vless', network: 'ws'),
  ServerEntry(
    name: '🇪🇺  Обход белых списков 1',
    type: 'vless',
    network: 'xhttp',
    section: 'Серверы для обхода белых списков',
  ),
  ServerEntry(
    name: awgDefaultName,
    type: 'wireguard',
    section: awgSectionTitle,
  ),
];

List<Group> _groups({required bool manual, String? now}) {
  final proxies = [
    for (final server in _servers) Proxy(name: server.name, type: server.type),
  ];
  return [
    Group(
      type: GroupType.Selector,
      name: mainGroupName,
      now: manual ? manualGroupName : autoGroupName,
      all: const [
        Proxy(name: autoGroupName, type: 'URLTest'),
        Proxy(name: manualGroupName, type: 'Selector'),
      ],
    ),
    Group(
      type: GroupType.URLTest,
      name: autoGroupName,
      now: manual ? null : _servers.first.name,
      all: proxies,
    ),
    Group(
      type: GroupType.Selector,
      name: manualGroupName,
      now: now ?? _servers.first.name,
      all: proxies,
    ),
  ];
}

/// Unmounts before the test ends so Riverpod's zero-delay dispose timers
/// fire inside the test instead of tripping the pending-timer check.
void _tv(String description, Future<void> Function(WidgetTester) body) {
  testWidgets(description, (tester) async {
    await body(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late _FakeCommonAction common;
  late _FakeProxiesAction proxies;
  late _FakeProfilesAction profiles;

  setUpAll(() {
    try {
      globalState.packageInfo;
    } on Error {
      globalState.packageInfo = PackageInfo(
        appName: 'TENVPN',
        packageName: 'com.tenvpn.app',
        version: '0.2.0',
        buildNumber: '2',
      );
    }
  });

  ProviderContainer build({
    List<Profile> items = const [],
    NetworkDetectionState detection = const NetworkDetectionState(
      isLoading: false,
      ipInfo: null,
    ),
    bool loaded = true,
  }) {
    common = _FakeCommonAction();
    proxies = _FakeProxiesAction();
    profiles = _FakeProfilesAction();
    final c = ProviderContainer(
      overrides: [
        profilesProvider.overrideWith(() => TestProfiles(items)),
        currentProfileIdProvider.overrideWithBuild(
          (_, _) => items.isEmpty ? null : items.first.id,
        ),
        commonActionProvider.overrideWith(() => common),
        proxiesActionProvider.overrideWith(() => proxies),
        profilesActionProvider.overrideWith(() => profiles),
        networkDetectionProvider.overrideWith(() => _FixedDetection(detection)),
        tenvpnServerEntriesProvider.overrideWith((_) async => _servers),
        profilesStreamProvider.overrideWith(
          (_) => loaded ? Stream.value(items) : const Stream.empty(),
        ),
      ],
    );
    globalState.container = c;
    c.read(viewSizeProvider.notifier).update((_) => const Size(420, 900));
    return c;
  }

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    AppLook look = AppLook.burrow,
  }) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          child: Theme(
            data: buildTenvpnTheme(brightness: Brightness.dark, look: look),
            child: child,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Finder text(String value) => find.textContaining(value, findRichText: true);

  final profile = Profile(
    id: 1,
    url: 'https://sub.example.com/x',
    autoUpdateDuration: const Duration(hours: 1),
    lastUpdateDate: DateTime.now(),
    subscriptionInfo: SubscriptionInfo(
      expire:
          DateTime.now().add(const Duration(days: 20)).millisecondsSinceEpoch ~/
          1000,
    ),
  );

  tearDown(() => container.dispose());

  group('main screen', () {
    _tv('off: one primary button that starts the tunnel', (tester) async {
      container = build(items: [profile]);
      container.read(groupsProvider.notifier).value = _groups(manual: false);
      await pump(tester, const TenvpnMainView());

      expect(find.text('Turn on'), findsOneWidget);
      expect(text('Tap to connect'), findsOneWidget);
      expect(find.byKey(const ValueKey('tenvpn-ring-off')), findsOneWidget);
      expect(text('Now: 🇸🇪 Швеция'), findsOneWidget);
      expect(text('Expires:'), findsOneWidget);
      expect(find.byType(FerMascot), findsNothing);

      await tester.tap(find.byKey(const ValueKey('tenvpn-connect')));
      expect(common.toggles, 1);
    });

    _tv('on: shows where the traffic exits', (tester) async {
      container = build(
        items: [profile],
        detection: const NetworkDetectionState(
          isLoading: false,
          ipInfo: IpInfo(ip: '203.0.113.7', countryCode: 'NL'),
        ),
      );
      container.read(runTimeProvider.notifier).value = 1;
      container.read(groupsProvider.notifier).value = _groups(
        manual: true,
        now: _servers[1].name,
      );
      await pump(tester, const TenvpnMainView());

      expect(find.text('On'), findsOneWidget);
      expect(find.byKey(const ValueKey('tenvpn-ring-on')), findsOneWidget);
      expect(text('Your IP: 🇳🇱 Netherlands'), findsOneWidget);
      expect(text('Белые списки 1'), findsOneWidget);
      expect(find.bySemanticsLabel('Disconnect'), findsOneWidget);
    });

    _tv('connecting is a short animation, then on until the check fails', (
      tester,
    ) async {
      container = build(
        items: [profile],
        detection: const NetworkDetectionState(isLoading: true, ipInfo: null),
      );
      await pump(tester, const TenvpnMainView());
      container.read(runTimeProvider.notifier).value = 1;
      await tester.pump();
      expect(find.text('Connecting'), findsOneWidget);
      expect(container.read(tenvpnPhaseProvider), ConnectionPhase.connecting);

      await tester.pump(connectingAnimation);
      expect(find.text('On'), findsOneWidget);
      expect(text('Connected'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      container.dispose();
      container = build(items: [profile]);
      container.read(runTimeProvider.notifier).value = 1;
      await pump(tester, const TenvpnMainView());
      expect(text('The server is not responding'), findsOneWidget);
      expect(find.text('No connection'), findsOneWidget);
      expect(find.byKey(const ValueKey('tenvpn-ring-error')), findsOneWidget);
    });

    _tv('hides the IP measured before the tunnel came up', (tester) async {
      container = build(
        items: [profile],
        detection: const NetworkDetectionState(
          isLoading: false,
          ipInfo: IpInfo(ip: '198.51.100.1', countryCode: 'RU'),
        ),
      );
      await pump(tester, const TenvpnMainView());
      container.read(runTimeProvider.notifier).value = 1;
      await tester.pump(connectingAnimation);
      expect(text('Russia'), findsNothing);
      expect(text('Connected'), findsOneWidget);

      container.read(networkDetectionProvider.notifier).state =
          const NetworkDetectionState(isLoading: true, ipInfo: null);
      await tester.pump();
      container
          .read(networkDetectionProvider.notifier)
          .state = const NetworkDetectionState(
        isLoading: false,
        ipInfo: IpInfo(ip: '203.0.113.7', countryCode: 'SE'),
      );
      await tester.pump();
      expect(text('Your IP: 🇸🇪 Sweden'), findsOneWidget);
    });

    _tv('expiry turns into a warning and an ended state', (tester) async {
      final soon = profile.copyWith(
        subscriptionInfo: SubscriptionInfo(
          expire:
              DateTime.now()
                  .add(const Duration(days: 1))
                  .millisecondsSinceEpoch ~/
              1000,
        ),
      );
      container = build(items: [soon]);
      await pump(tester, const TenvpnExpiryLine());
      expect(text('1 day left'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      container.dispose();
      container = build(
        items: [
          profile.copyWith(subscriptionInfo: const SubscriptionInfo(expire: 1)),
        ],
      );
      await pump(tester, const TenvpnExpiryLine());
      expect(text('Subscription has ended'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      container.dispose();
      container = build(items: [profile.copyWith(subscriptionInfo: null)]);
      await pump(tester, const TenvpnExpiryLine());
      expect(text('Expires: —'), findsOneWidget);
    });

    _tv('re-checks the IP when auto moves to another exit', (tester) async {
      container = build(items: [profile]);
      container.read(runTimeProvider.notifier).value = 1;
      container.read(groupsProvider.notifier).value = _groups(manual: false);
      await pump(tester, const TenvpnMainView());
      final before = container.read(checkIpNumProvider);

      final moved = _groups(manual: false);
      moved[1] = moved[1].copyWith(now: _servers[1].name);
      container.read(groupsProvider.notifier).value = moved;
      await tester.pump();

      expect(container.read(checkIpNumProvider), before + 1);
    });
  });

  group('servers screen', () {
    _tv('lists auto first, then labelled sections', (tester) async {
      container = build(items: [profile]);
      container.read(groupsProvider.notifier).value = _groups(manual: false);
      await pump(
        tester,
        Scaffold(body: ListView(children: const [TenvpnServerList()])),
      );
      await tester.pump();

      expect(proxies.speedChecks, 1);
      expect(text('For allowlisted networks · 1'), findsOneWidget);
      expect(text('Backup connection · 1'), findsOneWidget);
      expect(text('Белые списки 1'), findsNothing);
      expect(container.read(tenvpnHasAwgProvider), isTrue);

      await tester.tap(find.byKey(const ValueKey('tenvpn-section-mobile')));
      await tester.pump();
      expect(text('Белые списки 1'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tenvpn-section-reserve')));
      await tester.pump();
      expect(text('AmneziaWG'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('tenvpn-section-reserve')));
      await tester.pump();
      expect(text('AmneziaWG'), findsNothing);

      await tester.tap(
        find.byKey(ValueKey('tenvpn-server-${_servers[1].name}')),
      );
      await tester.pump();
      expect(proxies.selected, [_servers[1].name]);

      await tester.tap(find.byKey(const ValueKey('tenvpn-server-auto')));
      await tester.pump();
      expect(proxies.selected.last, isNull);

      await tester.tap(find.byKey(const ValueKey('tenvpn-ping')));
      expect(proxies.speedChecks, 2);
    });

    _tv('detailed look opens every section and keeps ping order', (
      tester,
    ) async {
      container = build(items: [profile]);
      container.read(groupsProvider.notifier).value = _groups(manual: false);
      container
          .read(appSettingProvider.notifier)
          .update(
            (s) => s.copyWith(
              serverListStyle: ServerListStyle.detailed,
              serverSort: ServerSort.ping,
            ),
          );
      await pump(
        tester,
        Scaffold(body: ListView(children: const [TenvpnServerList()])),
      );
      expect(text('Белые списки 1'), findsOneWidget);
      expect(text('AmneziaWG'), findsWidgets);
    });

    test('selection looks through the hidden «Авто» tiers', () {
      container = build(items: [profile]);
      for (final (tier, server) in [
        (autoPrimaryGroupName, 'NL'),
        (autoWhitelistGroupName, 'WL 1'),
        ('AWG', 'AWG'),
      ]) {
        container.read(groupsProvider.notifier).value = [
          const Group(
            type: GroupType.Selector,
            name: mainGroupName,
            now: autoGroupName,
          ),
          Group(type: GroupType.Fallback, name: autoGroupName, now: tier),
          const Group(
            type: GroupType.URLTest,
            name: autoPrimaryGroupName,
            now: 'NL',
          ),
          const Group(
            type: GroupType.URLTest,
            name: autoWhitelistGroupName,
            now: 'WL 1',
          ),
        ];
        expect(container.read(tenvpnSelectionProvider), (
          auto: true,
          server: server,
        ));
      }
    });
  });

  group('onboarding', () {
    _tv('rejects text that is not a link', (tester) async {
      container = build();
      await pump(tester, const TenvpnOnboardingView());

      expect(text('Let\'s connect in a minute'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('tenvpn-link-field')),
        'hello',
      );
      await tester.tap(find.text('Add'));
      await tester.pump();
      expect(find.byKey(const ValueKey('tenvpn-import-error')), findsOneWidget);
      expect(profiles.imported, isEmpty);
    });

    _tv('shows the import error in place', (tester) async {
      container = build();
      profiles.result = 'The server sent links instead of app settings';
      await pump(tester, const TenvpnOnboardingView());

      await tester.enterText(
        find.byKey(const ValueKey('tenvpn-link-field')),
        ' https://sub.example.com/abc ',
      );
      await tester.tap(find.text('Add'));
      await tester.pump();
      await tester.pump();
      expect(profiles.imported.single.$1, 'https://sub.example.com/abc');
      expect(profiles.imported.single.$3, isFalse);
      expect(text('links instead of app settings'), findsOneWidget);
    });

    _tv('replace mode closes itself after a good import', (tester) async {
      container = build(items: [profile]);
      await pump(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const TenvpnOnboardingView(replace: true),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('tenvpn-link-field')),
        'https://sub.example.com/new',
      );
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(profiles.imported.single.$3, isTrue);
      expect(find.byType(TenvpnOnboardingView), findsNothing);
    });
  });

  group('settings', () {
    _tv('toggles, theme and the protocol choice', (tester) async {
      container = build(items: [profile]);
      container.read(groupsProvider.notifier).value = _groups(manual: false);
      await pump(tester, const TenvpnSettingsView());
      await tester.pump();

      expect(find.byType(FerMascot), findsOneWidget);
      expect(text('Connect on launch'), findsOneWidget);
      await tester.tap(find.text('Connect on launch'));
      await tester.pump();
      expect(container.read(appSettingProvider).autoRun, isTrue);

      expect(container.read(themeSettingProvider).themeMode, ThemeMode.dark);
      await tester.tap(find.text('Light'));
      await tester.pump();
      expect(container.read(themeSettingProvider).themeMode, ThemeMode.light);

      expect(find.byKey(const ValueKey('tenvpn-protocol')), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('tenvpn-sort')),
        200,
      );
      await tester.ensureVisible(find.text('Detailed'));
      await tester.pump();
      await tester.tap(find.text('Detailed'));
      await tester.pump();
      expect(
        container.read(appSettingProvider).serverListStyle,
        ServerListStyle.detailed,
      );
      await tester.ensureVisible(find.text('By ping'));
      await tester.pump();
      await tester.tap(find.text('By ping'));
      await tester.pump();
      expect(container.read(appSettingProvider).serverSort, ServerSort.ping);

      await tester.scrollUntilVisible(text('Refresh subscription'), -200);
      expect(text('Refresh subscription'), findsOneWidget);
      await tester.scrollUntilVisible(text('Advanced'), 200);
      expect(text('Advanced'), findsOneWidget);

      await tester.scrollUntilVisible(text('Technical statistics'), 200);
      expect(container.read(appSettingProvider).tenvpnTelemetry, isTrue);
      await tester.tap(text('Technical statistics'));
      await tester.pump();
      expect(container.read(appSettingProvider).tenvpnTelemetry, isFalse);
      await tester.scrollUntilVisible(text('Privacy policy'), 200);
      expect(text('Privacy policy'), findsOneWidget);
    });

    _tv('the strict look is picked in settings and hides Fer', (tester) async {
      container = build(items: [profile]);
      await pump(tester, const TenvpnSettingsView());
      await tester.ensureVisible(find.text('Strict'));
      await tester.pump();
      await tester.tap(find.text('Strict'));
      await tester.pump();
      expect(container.read(appSettingProvider).look, AppLook.strict);

      await pump(tester, const TenvpnSettingsView(), look: AppLook.strict);
      await tester.drag(find.byType(ListView), const Offset(0, 3000));
      await tester.pump();
      expect(find.byType(Image), findsNothing);
      expect(find.byType(TenvpnLogo), findsOneWidget);
    });

    _tv('advanced keeps the base client reachable', (tester) async {
      container = build(items: [profile]);
      await pump(tester, const TenvpnAdvancedView());
      expect(find.text('Profiles'), findsOneWidget);
      expect(find.text('Proxies'), findsOneWidget);
    });
  });

  group('home', () {
    _tv('onboarding without a subscription, main screen with one', (
      tester,
    ) async {
      container = build();
      await pump(tester, const TenvpnHome());
      await tester.pumpAndSettle();
      expect(find.byType(TenvpnOnboardingView), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      container.dispose();
      container = build(items: [profile]);
      await pump(tester, const TenvpnHome());
      await tester.pumpAndSettle();
      expect(find.byType(TenvpnMainView), findsOneWidget);
    });

    _tv('nothing flashes before the profiles are read', (tester) async {
      container = build(loaded: false);
      await pump(tester, const TenvpnHome());
      expect(find.byType(TenvpnSplash), findsOneWidget);
      expect(find.byType(TenvpnOnboardingView), findsNothing);
      expect(find.byType(TenvpnMainView), findsNothing);
    });
  });

  test('palettes interpolate and default to dark', () {
    final mid = TenvpnPalette.dark.lerp(TenvpnPalette.light, 0.5);
    expect(mid.accent, TenvpnPalette.dark.accent);
    expect(TenvpnPalette.dark.lerp(null, 0.5), TenvpnPalette.dark);
    expect(TenvpnPalette.dark.copyWith(), TenvpnPalette.dark);
    expect(
      buildTenvpnTheme(brightness: Brightness.light).colorScheme.brightness,
      Brightness.light,
    );
  });

  test('the strict palette keeps lime and drops cocoa and Fer', () {
    for (final brightness in Brightness.values) {
      final warm = TenvpnPalette.of(brightness, AppLook.burrow);
      final strict = TenvpnPalette.of(brightness, AppLook.strict);
      expect(warm.showMascot, isTrue);
      expect(strict.showMascot, isFalse);
      expect(strict.accent, warm.accent);
      expect(strict.cocoaText, isNot(warm.cocoaText));
    }
    expect(
      TenvpnPalette.dark.lerp(TenvpnPalette.strictDark, 0.9).showMascot,
      isFalse,
    );
  });

  test('every Fer drawing the app can pick is bundled', () {
    for (final entry in ferVariants.entries) {
      for (var variant = 1; variant <= entry.value; variant++) {
        final asset = ferAsset(entry.key, variant);
        expect(File(asset).existsSync(), isTrue, reason: asset);
      }
    }
  });

  _tv('Fer picks a fresh drawing when the pose changes', (tester) async {
    container = build();
    Widget fer(FerPose pose) => FerMascot(pose: pose, random: Random(1));
    await pump(tester, fer(FerPose.off));
    expect(find.byType(Image), findsOneWidget);
    await pump(tester, fer(FerPose.on));
    await tester.pump(const Duration(seconds: 1));
    final image = tester.widget<Image>(find.byType(Image));
    expect(
      (image.image as AssetImage).assetName,
      startsWith('assets/images/mascot/on-'),
    );
  });
}
