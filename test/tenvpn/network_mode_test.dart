import 'dart:async';

import 'package:fl_clash/tenvpn/configgen/constants.dart';
import 'package:fl_clash/tenvpn/network_mode.dart';
import 'package:flutter_test/flutter_test.dart';

DirectProbe probeWith({required bool whitelist, required bool open}) =>
    (url, timeout) async {
      expect(timeout, networkProbeTimeout);
      if (whitelistProbeUrls.contains(url)) return whitelist;
      if (openProbeUrls.contains(url)) return open;
      fail('unexpected probe $url');
    };

void main() {
  test('classifies by what answers directly', () {
    expect(
      classifyNetwork(whitelistReachable: true, openReachable: true),
      NetworkMode.open,
    );
    expect(
      classifyNetwork(whitelistReachable: true, openReachable: false),
      NetworkMode.whitelist,
    );
    expect(
      classifyNetwork(whitelistReachable: false, openReachable: false),
      NetworkMode.offline,
    );
    expect(
      classifyNetwork(whitelistReachable: false, openReachable: true),
      NetworkMode.open,
    );
  });

  test('one reachable target per side is enough, a throw is a miss', () async {
    final mode = await detectNetworkMode((url, _) async {
      if (url == whitelistProbeUrls.last) return true;
      if (url == openProbeUrls.first) throw StateError('no route');
      return false;
    });
    expect(mode, NetworkMode.whitelist);
    expect(
      await detectNetworkMode(probeWith(whitelist: true, open: true)),
      NetworkMode.open,
    );
    expect(
      await detectNetworkMode(probeWith(whitelist: false, open: false)),
      NetworkMode.offline,
    );
  });

  test('pins the whitelist tier, hands back the order, ignores offline', () {
    expect(
      autoPinFor(NetworkMode.whitelist, hasWhitelistTier: true),
      autoWhitelistGroupName,
    );
    expect(autoPinFor(NetworkMode.whitelist, hasWhitelistTier: false), isNull);
    expect(autoPinFor(NetworkMode.open, hasWhitelistTier: true), '');
    expect(autoPinFor(NetworkMode.offline, hasWhitelistTier: true), isNull);
  });

  group('NetworkModeController', () {
    late List<(String, bool)> pins;
    late bool whitelist;
    late bool open;
    late bool hasTier;
    late NetworkModeController controller;

    setUp(() {
      pins = [];
      whitelist = true;
      open = true;
      hasTier = true;
      controller = NetworkModeController(
        probe: (url, timeout) async =>
            whitelistProbeUrls.contains(url) ? whitelist : open,
        pin: (tier, {required changed}) async => pins.add((tier, changed)),
        hasWhitelistTier: () => hasTier,
      );
    });

    test('Wi-Fi → whitelisted mobile → Wi-Fi', () async {
      expect(await controller.refresh(), NetworkMode.open);
      open = false;
      expect(await controller.refresh(), NetworkMode.whitelist);
      expect(controller.mode, NetworkMode.whitelist);
      open = true;
      expect(await controller.refresh(), NetworkMode.open);
      expect(pins, [('', false), (autoWhitelistGroupName, true), ('', true)]);
    });

    test('no network leaves «Авто» as it is', () async {
      open = false;
      await controller.refresh();
      whitelist = false;
      expect(await controller.refresh(), NetworkMode.offline);
      expect(pins, [(autoWhitelistGroupName, true)]);
    });

    test('without a whitelist tier nothing is pinned', () async {
      hasTier = false;
      open = false;
      expect(await controller.refresh(), NetworkMode.whitelist);
      expect(pins, isEmpty);
    });

    test('a newer refresh or a stop wins over a slow probe', () async {
      final gate = Completer<void>();
      final slow = NetworkModeController(
        probe: (url, _) async {
          await gate.future;
          return true;
        },
        pin: (tier, {required changed}) async => pins.add((tier, changed)),
        hasWhitelistTier: () => true,
      );
      final pending = slow.refresh();
      slow.reset();
      gate.complete();
      expect(await pending, isNull);
      expect(pins, isEmpty);
      expect(slow.mode, isNull);
    });
  });
}
