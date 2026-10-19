import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/tenvpn/network_mode.dart';
import 'package:fl_clash/views/tenvpn/network_mode_tasks.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late StreamController<List<ConnectivityResult>> network;
  late int probes;
  late List<String> pins;

  setUp(() {
    container = ProviderContainer();
    globalState.container = container;
    network = StreamController.broadcast();
    probes = 0;
    pins = [];
  });

  tearDown(() async {
    await network.close();
    container.dispose();
  });

  Future<void> pump(WidgetTester tester) async {
    final controller = NetworkModeController(
      probe: (url, _) async {
        probes++;
        return true;
      },
      pin: (tier, {required changed}) async => pins.add(tier),
      hasWhitelistTier: () => true,
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: TestApp(
          child: TenvpnNetworkModeTasks(
            connectivity: network.stream,
            controller: controller,
            child: const SizedBox(key: Key('child')),
          ),
        ),
      ),
    );
  }

  testWidgets('probes after connecting and after a network change', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byKey(const Key('child')), findsOneWidget);

    network.add([ConnectivityResult.wifi]);
    await tester.pump(const Duration(seconds: 2));
    expect(probes, 0, reason: 'nothing to steer while the VPN is off');

    container.read(runTimeProvider.notifier).value = 1;
    await tester.pump(const Duration(seconds: 2));
    final afterConnect = probes;
    expect(afterConnect, greaterThan(0));
    expect(pins, ['']);

    network.add([ConnectivityResult.mobile]);
    network.add([ConnectivityResult.mobile, ConnectivityResult.vpn]);
    await tester.pump(const Duration(seconds: 2));
    expect(probes, 2 * afterConnect, reason: 'bursts settle into one probe');

    container.read(runTimeProvider.notifier).value = null;
    network.add([ConnectivityResult.wifi]);
    await tester.pump(const Duration(seconds: 2));
    expect(probes, 2 * afterConnect);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
