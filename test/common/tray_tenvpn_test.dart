import 'package:fl_clash/common/app_localizations.dart';
import 'package:fl_clash/common/tray.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/tenvpn/configgen/constants.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:riverpod/riverpod.dart';
import 'package:tray/tray.dart';

import '../helpers/test_profiles.dart';

const _channel = MethodChannel('tray');

class _RecordingProxiesAction extends ProxiesAction {
  final selected = <String?>[];

  @override
  void build() {}

  @override
  Future<void> selectTenvpnServer(String? serverName) async {
    selected.add(serverName);
  }
}

class _RecordingCommonAction extends CommonAction {
  int toggles = 0;
  int reconnects = 0;

  @override
  void build() {}

  @override
  void toggleRunning() => toggles++;

  @override
  Future<void> reconnect() async => reconnects++;
}

List<Group> _groups({required bool auto, String manualNow = 'NL'}) => [
  Group(
    name: mainGroupName,
    type: GroupType.Selector,
    now: auto ? autoGroupName : manualGroupName,
    all: const [
      Proxy(name: autoGroupName, type: 'Fallback'),
      Proxy(name: manualGroupName, type: 'Selector'),
    ],
  ),
  const Group(
    name: autoGroupName,
    type: GroupType.Fallback,
    now: 'AWG',
    all: [
      Proxy(name: 'AWG', type: 'WireGuard'),
      Proxy(name: 'NL', type: 'Vless'),
    ],
  ),
  Group(
    name: manualGroupName,
    type: GroupType.Selector,
    now: manualNow,
    all: const [
      Proxy(name: 'NL', type: 'Vless'),
      Proxy(name: 'SE', type: 'Vless'),
      Proxy(name: 'AWG', type: 'WireGuard'),
    ],
  ),
];

TrayState _state({bool isStart = false, List<Group> groups = const []}) {
  return TrayState(
    mode: Mode.rule,
    port: 7890,
    autoLaunch: true,
    systemProxy: false,
    tunEnable: true,
    isStart: isStart,
    groups: groups,
    selectedMap: const {},
    showNetworkSpeed: false,
    monochromeTrayIcon: false,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<MethodCall> calls;
  late ProviderContainer container;
  late _RecordingProxiesAction proxies;
  late _RecordingCommonAction common;
  final tray = AppTray.forPlatform(
    isMacOS: false,
    isWindows: true,
    tenvpnMenu: true,
  );

  setUpAll(() async {
    await AppLocalizations.load(const Locale('ru'));
  });

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    calls = [];
    proxies = _RecordingProxiesAction();
    common = _RecordingCommonAction();
    container = ProviderContainer(
      overrides: [
        proxiesActionProvider.overrideWith(() => proxies),
        commonActionProvider.overrideWith(() => common),
      ],
    );
    Tray.instance.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          return true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    container.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  Map<Object?, Object?> showArgs() =>
      calls.lastWhere((call) => call.method == 'show').arguments as Map;

  List<Map<Object?, Object?>> items() =>
      (showArgs()['menu'] as List).cast<Map<Object?, Object?>>();

  Map<Object?, Object?> byLabel(String label) =>
      items().singleWhere((item) => item['label'] == label);

  List<Map<Object?, Object?>> servers() =>
      (byLabel(currentAppLocalizations.tenvpnServer)['items'] as List)
          .cast<Map<Object?, Object?>>()
          .where((item) => item['label'] != null)
          .toList();

  Future<void> update(TrayState state) => tray.update(
    trayState: state,
    traffic: const Traffic(),
    read: container.read,
  );

  Future<void> select(Map<Object?, Object?> item) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          _channel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('onMenuItemSelected', {'id': item['id']}),
          ),
          (_) {},
        );
  }

  test(
    'short menu: open, power, reconnect, servers, autostart, exit',
    () async {
      final l = currentAppLocalizations;
      await update(_state(groups: _groups(auto: true)));
      expect(items().map((item) => item['label']).whereType<String>(), [
        l.tenvpnTrayOpen,
        l.tenvpnConnect,
        l.tenvpnReconnect,
        l.tenvpnServer,
        l.tenvpnTrayAutoStart,
        l.exit,
      ]);
      expect(byLabel(l.tenvpnReconnect)['enabled'], isFalse);
      expect(byLabel(l.tenvpnTrayAutoStart)['checked'], isTrue);
      expect(showArgs()['toolTip'], 'TENVPN');
    },
  );

  test('running: disconnect, reconnect enabled, status in tooltip', () async {
    final l = currentAppLocalizations;
    await update(_state(isStart: true, groups: _groups(auto: true)));
    expect(byLabel(l.tenvpnDisconnect), isNotNull);
    expect(byLabel(l.tenvpnReconnect)['enabled'], isTrue);
    expect(showArgs()['toolTip'], 'TENVPN · ${l.tenvpnPowerOnState}');

    await select(byLabel(l.tenvpnDisconnect));
    await select(byLabel(l.tenvpnReconnect));
    expect(common.toggles, 1);
    expect(common.reconnects, 1);
  });

  test('server submenu mirrors «Авто» and «Вручную»', () async {
    final l = currentAppLocalizations;
    await update(_state(groups: _groups(auto: true)));
    expect(byLabel(l.tenvpnServer)['sublabel'], l.tenvpnAuto);
    expect(servers().map((item) => item['label']), [
      l.tenvpnAuto,
      'NL',
      'SE',
      'AWG',
    ]);
    expect(servers().map((item) => item['checked']), [
      true,
      false,
      false,
      false,
    ]);

    // A fresh show call instead of an incremental menu patch.
    Tray.instance.resetForTesting();
    await update(_state(groups: _groups(auto: false, manualNow: 'SE')));
    expect(byLabel(l.tenvpnServer)['sublabel'], 'SE');
    expect(servers().map((item) => item['checked']), [
      false,
      false,
      true,
      false,
    ]);

    await select(servers()[3]);
    await select(servers()[0]);
    expect(proxies.selected, ['AWG', null]);
  });

  test('no servers yet: no server submenu', () async {
    await update(_state());
    expect(
      items().where(
        (item) => item['label'] == currentAppLocalizations.tenvpnServer,
      ),
      isEmpty,
    );
  });

  test('developer mode brings back the full upstream menu', () async {
    container.dispose();
    container = ProviderContainer(
      overrides: [
        appSettingProvider.overrideWithValue(
          const AppSettingProps(developerMode: true),
        ),
        profilesProvider.overrideWith(() => TestProfiles(const [])),
      ],
    );
    await update(_state(groups: _groups(auto: true)));
    final labels = items().map((item) => item['label']).toList();
    expect(labels, contains(currentAppLocalizations.systemProxy));
    expect(labels, isNot(contains(currentAppLocalizations.tenvpnReconnect)));
  });

  test('tenvpnTraySelection falls back to «Авто» without groups', () {
    expect(tenvpnTraySelection(const []), (
      auto: true,
      servers: const <String>[],
      selected: null,
    ));
  });
}
