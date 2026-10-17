import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/tenvpn/tenvpn.dart';
import 'package:fl_clash/views/tenvpn/account_tasks.dart';
import 'package:fl_clash/views/tenvpn/main_view.dart';
import 'package:fl_clash/views/tenvpn/privacy_view.dart';
import 'package:fl_clash/views/tenvpn/state.dart';
import 'package:fl_clash/views/tenvpn/theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../helpers/test_app.dart';
import '../helpers/test_profiles.dart';

class _MemoryConfig extends TenvpnConfigService {
  String? token = 'tok';
  String? notice;
  AccountCache? cached;
  int refreshes = 0;

  _MemoryConfig()
    : super(
        store: TenvpnStateStore(() async => ''),
        transport: (_, _) async => const AwgHttpResponse(500, ''),
      );

  @override
  Future<String?> appToken(int profileId) async => token;

  @override
  Future<AccountCache?> account(int profileId) async => cached;

  @override
  Future<AccountCache?> refreshAccount(int profileId) async {
    refreshes++;
    return cached;
  }

  @override
  Future<String?> expiryNoticeFor(int profileId) async => notice;

  @override
  Future<void> markExpiryNotice(int profileId, String key) async =>
      notice = key;
}

class _Phase extends Notifier<ConnectionPhase> {
  @override
  ConnectionPhase build() => ConnectionPhase.off;

  void set(ConnectionPhase phase) => state = phase;
}

final _phaseProvider = NotifierProvider<_Phase, ConnectionPhase>(_Phase.new);

class _MemoryBundle extends CachingAssetBundle {
  final String text;

  _MemoryBundle(this.text);

  @override
  Future<ByteData> load(String key) async =>
      ByteData.sublistView(Uint8List.fromList(text.codeUnits));

  @override
  Future<String> loadString(String key, {bool cache = true}) async => text;
}

AccountCache _account({
  int daysLeft = 13,
  String status = 'active',
  int devices = 3,
}) => AccountCache(
  account: AccountInfo(
    balanceRub: 91.4,
    dailyRateRub: 9,
    daysLeft: daysLeft,
    activeDevices: devices,
    status: AccountStatus.values.byName(status),
    renewUrl: 'https://t.me/Tenvpnrobot?start=app_renew',
  ),
  fetchedAt: DateTime.now(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  var cabinetOpens = 0;
  late _MemoryConfig config;
  late List<Map<String, String>> notices;
  late List<ConnectEvent> events;

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

  const profile = Profile(
    id: 7,
    url: 'https://sub.example.com/abc',
    autoUpdateDuration: Duration(hours: 1),
  );

  ProviderContainer build({AccountCache? account}) {
    config = _MemoryConfig()..cached = account;
    cabinetOpens = 0;
    notices = [];
    events = [];
    final c = ProviderContainer(
      overrides: [
        tenvpnOpenCabinetProvider.overrideWithValue(() async {
          cabinetOpens++;
        }),
        profilesProvider.overrideWith(() => TestProfiles([profile])),
        currentProfileIdProvider.overrideWithBuild((_, _) => profile.id),
        tenvpnConfigProvider.overrideWithValue(config),
        tenvpnAccountProvider.overrideWith((_) async => account),
        tenvpnPhaseProvider.overrideWith((ref) => ref.watch(_phaseProvider)),
        tenvpnSelectionProvider.overrideWithValue((auto: false, server: 'NL')),
        tenvpnServerEntriesProvider.overrideWith(
          (_) async => const [
            ServerEntry(name: 'NL', type: 'vless', security: 'reality'),
          ],
        ),
        showAccountNoticeProvider.overrideWithValue(({
          required channelName,
          required title,
          required text,
          required actionLabel,
          required actionUrl,
        }) async {
          notices.add({'title': title, 'text': text, 'url': actionUrl});
          return true;
        }),
        sendConnectEventProvider.overrideWithValue((token, event) async {
          expect(token, 'tok');
          events.add(event);
          return true;
        }),
      ],
    );
    globalState.container = c;
    return c;
  }

  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          child: Theme(
            data: buildTenvpnTheme(brightness: Brightness.dark),
            child: Scaffold(body: child),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    container.dispose();
  }

  Finder text(String value) => find.textContaining(value, findRichText: true);

  testWidgets('balance, devices and the cabinet button from the account', (
    tester,
  ) async {
    container = build(account: _account());
    await pump(tester, const TenvpnExpiryLine());
    expect(text('Paid until'), findsOneWidget);
    expect(text('13 days left'), findsOneWidget);
    expect(text('Balance 91 ₽ · 9 ₽ a day · 3 devices'), findsOneWidget);
    expect(find.byKey(const ValueKey('tenvpn-cabinet')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tenvpn-cabinet')));
    expect(cabinetOpens, 1);
    expect(
      container.read(tenvpnRenewUrlProvider),
      'https://t.me/Tenvpnrobot?start=app_renew',
    );
    await unmount(tester);
  });

  testWidgets('suspended and free accounts read differently', (tester) async {
    container = build(account: _account(status: 'suspended', daysLeft: 0));
    await pump(tester, const TenvpnExpiryLine());
    expect(text('Access paused'), findsOneWidget);
    await unmount(tester);

    container = build(account: _account(status: 'free', daysLeft: 999));
    await pump(tester, const TenvpnExpiryLine());
    expect(text('Free access'), findsOneWidget);
    expect(find.byKey(const ValueKey('tenvpn-balance')), findsNothing);
    await unmount(tester);
  });

  testWidgets('without an account Renew opens the bot', (tester) async {
    container = build();
    await pump(tester, const TenvpnExpiryLine());
    expect(text('Expires: —'), findsOneWidget);
    expect(container.read(tenvpnRenewUrlProvider), tenvpnBotUrl);
    await unmount(tester);
  });

  testWidgets('the 2-day notice is shown once per paid-until date', (
    tester,
  ) async {
    container = build(account: _account(daysLeft: 2));
    await pump(tester, const TenvpnAccountTasks(child: SizedBox()));
    await tester.pump();
    expect(notices, hasLength(1));
    expect(notices.single['title'], 'Your subscription is ending');
    expect(notices.single['url'], 'https://t.me/Tenvpnrobot?start=app_renew');
    expect(config.notice, isNotNull);
    await unmount(tester);

    final shown = config.notice;
    container = build(account: _account(daysLeft: 2));
    config.notice = shown;
    await pump(tester, const TenvpnAccountTasks(child: SizedBox()));
    await tester.pump();
    expect(notices, isEmpty);
    await unmount(tester);

    container = build(account: _account(daysLeft: 5));
    await pump(tester, const TenvpnAccountTasks(child: SizedBox()));
    await tester.pump();
    expect(notices, isEmpty);
    await unmount(tester);
  });

  testWidgets('a connect event goes out only when the switch is on', (
    tester,
  ) async {
    container = build(account: _account());
    final settings = container.listen(appSettingProvider, (_, _) {});
    addTearDown(settings.close);
    await pump(tester, const TenvpnAccountTasks(child: SizedBox()));
    Future<void> phase(ConnectionPhase value) async {
      container.read(_phaseProvider.notifier).set(value);
      await tester.pump();
      await tester.pump();
    }

    container
        .read(appSettingProvider.notifier)
        .update((s) => s.copyWith(tenvpnTelemetry: false));
    await phase(ConnectionPhase.on);
    expect(events, isEmpty);

    await phase(ConnectionPhase.off);
    container
        .read(appSettingProvider.notifier)
        .update((s) => s.copyWith(tenvpnTelemetry: true));
    await phase(ConnectionPhase.on);
    expect(events.single.protocol, 'vless-reality');
    expect(events.single.appVersion, '0.2.0');
    await unmount(tester);
  });

  testWidgets('the privacy page renders the bundled policy', (tester) async {
    container = build();
    await pump(
      tester,
      TenvpnPrivacyView(
        bundle: _MemoryBundle(
          '# Title\n\n## Part\n\n- one\n- two\n\nBody **bold**.',
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Title'), findsOneWidget);
    expect(find.text('one'), findsOneWidget);
    expect(find.text('Body bold.'), findsOneWidget);
    await unmount(tester);
  });
}
