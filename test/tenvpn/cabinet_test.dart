import 'package:fl_clash/tenvpn/account.dart';
import 'package:fl_clash/tenvpn/awg_source.dart';
import 'package:fl_clash/tenvpn/cabinet.dart';
import 'package:flutter_test/flutter_test.dart';

const _api = TenvpnEndpoints('https://cabinet.example.com');
const _bot = 'https://t.me/Tenvpnrobot?start=src_app';

void main() {
  late List<(Uri, Map<String, String>)> calls;

  setUp(() => calls = []);

  Future<AwgHttpResponse> Function(Uri, Map<String, String>, String) answer(
    int status,
    String body,
  ) => (uri, headers, _) async {
    calls.add((uri, headers));
    return AwgHttpResponse(status, body);
  };

  test('the signed-in link is posted for with the device token', () async {
    final url = await cabinetUrl(
      endpoints: _api,
      token: 'tok',
      fallback: _bot,
      post: answer(
        200,
        '{"version":1,"url":"https://cabinet.example.com/app/login?c=x"}',
      ),
    );
    expect(url, 'https://cabinet.example.com/app/login?c=x');
    final (uri, headers) = calls.single;
    expect(
      uri.toString(),
      'https://cabinet.example.com/api/app/v1/cabinet_link',
    );
    expect(headers['Authorization'], 'Bearer tok');
  });

  test('a link to another host or over http is ignored', () async {
    for (final body in [
      '{"url":"https://evil.example.org/login"}',
      '{"url":"http://cabinet.example.com/login"}',
      'not json',
    ]) {
      expect(
        await cabinetUrl(
          endpoints: _api,
          token: 'tok',
          fallback: _bot,
          post: answer(200, body),
        ),
        'https://cabinet.example.com/',
      );
    }
  });

  test('errors, no token and no backend fall back', () async {
    expect(
      await cabinetUrl(
        endpoints: _api,
        token: 'tok',
        fallback: _bot,
        post: answer(404, ''),
      ),
      'https://cabinet.example.com/',
    );
    expect(
      await cabinetUrl(
        endpoints: _api,
        token: null,
        fallback: _bot,
        post: answer(200, '{}'),
      ),
      'https://cabinet.example.com/',
    );
    expect(calls.length, 1);
    expect(
      await cabinetUrl(
        endpoints: null,
        token: 'tok',
        fallback: _bot,
        post: answer(200, '{}'),
      ),
      _bot,
    );
  });
}
