import 'dart:math';

import 'package:fl_clash/models/models.dart';

import 'configgen/builder.dart';

const localProxyUser = 'tenvpn';

/// Any Android app can reach the core's loopback port and learn our exit IP.
Config withLocalProxyAuth(
  Config config, {
  required bool isAndroid,
  Random? random,
}) {
  if (!isAndroid) return config;
  final network = config.networkProps;
  if (network.authentication.credentials.isNotEmpty &&
      network.authentication.password.isNotEmpty) {
    return config;
  }
  return config.copyWith(
    networkProps: network.copyWith(
      authentication: AuthenticationProps(
        enable: true,
        username: localProxyUser,
        password: generateSecret(random),
      ),
    ),
  );
}
