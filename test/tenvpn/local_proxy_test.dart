import 'dart:math';

import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/tenvpn/local_proxy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const config = Config(themeProps: defaultThemeProps);

  test('Android gets a random password on the local proxy, once', () {
    final secured = withLocalProxyAuth(
      config,
      isAndroid: true,
      random: Random(1),
    );
    final auth = secured.networkProps.authentication;
    expect(auth.enable, isTrue);
    expect(auth.username, localProxyUser);
    expect(auth.password, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(auth.credentials, ['$localProxyUser:${auth.password}']);
    expect(withLocalProxyAuth(secured, isAndroid: true), same(secured));
  });

  test('desktop and an existing password are left alone', () {
    expect(withLocalProxyAuth(config, isAndroid: false), same(config));
    final own = config.copyWith(
      networkProps: const NetworkProps(
        authentication: AuthenticationProps(
          enable: true,
          username: 'me',
          password: 'secret',
        ),
      ),
    );
    expect(withLocalProxyAuth(own, isAndroid: true), same(own));
  });

  test('an enabled login without a password is replaced', () {
    final weak = config.copyWith(
      networkProps: const NetworkProps(
        authentication: AuthenticationProps(enable: true, username: 'me'),
      ),
    );
    final secured = withLocalProxyAuth(weak, isAndroid: true);
    expect(secured.networkProps.authentication.password, isNotEmpty);
  });
}
