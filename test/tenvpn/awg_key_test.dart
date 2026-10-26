import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fl_clash/tenvpn/awg_key.dart';
import 'package:flutter_test/flutter_test.dart';

String _amneziaShare(Object json) {
  final body = utf8.encode(jsonEncode(json));
  final length = ByteData(4)..setUint32(0, body.length);
  final packed = [...length.buffer.asUint8List(), ...zlib.encode(body)];
  return 'vpn://${base64Url.encode(packed).replaceAll('=', '')}';
}

void main() {
  final conf = File('test/fixtures/tenvpn/awg_v3.conf').readAsStringSync();

  test('a pasted .conf is taken as it is', () {
    expect(decodeAwgKey('\n$conf\n'), conf.trim());
  });

  test('an AmneziaVPN vpn:// share yields the AWG container config', () {
    final share = _amneziaShare({
      'containers': [
        {
          'container': 'amnezia-awg',
          'awg': {
            'last_config': jsonEncode({'config': conf, 'port': '51820'}),
          },
        },
      ],
      'defaultContainer': 'amnezia-awg',
      'description': 'TENVPN',
    });
    expect(decodeAwgKey(share), conf.trim());
    expect(
      decodeAwgKey(share.toUpperCase().substring(0, 6) + share.substring(6)),
      conf.trim(),
    );
  });

  test('says why a key cannot be used', () {
    AwgKeyError errorOf(String text) {
      try {
        decodeAwgKey(text);
      } on AwgKeyException catch (e) {
        return e.error;
      }
      fail('no error for $text');
    }

    expect(errorOf('  '), AwgKeyError.empty);
    expect(errorOf('https://sub.example.com/x'), AwgKeyError.notAwg);
    expect(errorOf('vpn://!!!'), AwgKeyError.unreadable);
    expect(
      errorOf(
        _amneziaShare({
          'api_config': {'service': 'free'},
        }),
      ),
      AwgKeyError.notAwg,
    );
  });
}
