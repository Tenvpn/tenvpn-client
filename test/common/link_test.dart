import 'dart:async';

import 'package:fl_clash/common/link.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late StreamController<Uri> links;
  late List<String> received;

  setUp(() {
    links = StreamController<Uri>.broadcast();
    received = [];
    linkManager.uriLinkStream = () => links.stream;
  });

  tearDown(() async {
    linkManager.destroy();
    await links.close();
  });

  Future<void> listen() async {
    await linkManager.initAppLinksListen(received.add);
  }

  Future<void> emit(String uri) async {
    links.add(Uri.parse(uri));
    await Future<void>.delayed(Duration.zero);
  }

  test('LinkManager is a singleton', () {
    expect(LinkManager(), same(linkManager));
  });

  test('an install-config link reports its url', () async {
    await listen();

    await emit('tenvpn://install-config?url=https://example.com/a.yaml');

    expect(received, ['https://example.com/a.yaml']);
  });

  test('an install-config link without a url is ignored', () async {
    await listen();

    await emit('tenvpn://install-config');

    expect(received, isEmpty);
  });

  test('awg parameters go to the TENVPN callback when it is set', () async {
    final tenvpn = <List<String>>[];
    await linkManager.initAppLinksListen(
      received.add,
      installTenvpnCallBack: (url, awgUrl, token) =>
          tenvpn.add([url, awgUrl, token]),
    );

    await emit(
      'tenvpn://install-config?url=https%3A%2F%2Fsub.example.com%2Fabc'
      '&awg=https%3A%2F%2Fapi.example.com%2Fapi%2Fapp%2Fv1%2Fawg&awg_token=t0k',
    );
    await emit(
      'tenvpn://install-config?url=https://example.com/a.yaml&awg=x&awg_token=',
    );

    expect(tenvpn, [
      [
        'https://sub.example.com/abc',
        'https://api.example.com/api/app/v1/awg',
        't0k',
      ],
    ]);
    expect(received, ['https://example.com/a.yaml']);
  });

  test('without a TENVPN callback awg parameters are ignored', () async {
    await listen();

    await emit('tenvpn://install-config?url=https://e.com/a&awg=x&awg_token=t');

    expect(received, ['https://e.com/a']);
  });

  test('a link for another host is ignored', () async {
    await listen();

    await emit('flclash://open-profile?url=https://example.com/a.yaml');

    expect(received, isEmpty);
  });

  test('listening again replaces the previous subscription', () async {
    await listen();
    final first = linkManager.subscription;

    await listen();

    expect(linkManager.subscription, isNot(same(first)));

    await emit('tenvpn://install-config?url=https://example.com/a.yaml');

    expect(received, ['https://example.com/a.yaml']);
  });

  test(
    'a seeded launch argument is delivered once a listener attaches',
    () async {
      linkManager.seedInitialLink([
        '--verbose',
        'tenvpn://install-config?url=https://example.com/a.yaml',
      ]);

      expect(received, isEmpty);

      await listen();

      expect(received, ['https://example.com/a.yaml']);

      await listen();

      expect(received, ['https://example.com/a.yaml']);
    },
  );

  test('launch arguments without a known scheme are ignored', () async {
    linkManager.seedInitialLink(['https://example.com/a.yaml', 'not a uri']);

    await listen();

    expect(received, isEmpty);
  });

  test('destroy stops delivery and is safe to repeat', () async {
    await listen();

    linkManager.destroy();
    linkManager.destroy();
    await emit('tenvpn://install-config?url=https://example.com/a.yaml');

    expect(linkManager.subscription, isNull);
    expect(received, isEmpty);
  });
}
