import 'package:dio/dio.dart';
import 'package:fl_clash/common/exception.dart';
import 'package:fl_clash/common/request.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/tenvpn/store.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await AppLocalizations.load(const Locale('en'));
  });

  test('getTextResponseForUrl propagates the typed DioException', () async {
    // flutter_test's mocked HttpClient answers every request with HTTP 400,
    // which Dio surfaces as a badResponse DioException.
    await expectLater(
      request.getTextResponseForUrl('http://127.0.0.1/anything'),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.badResponse,
        ),
      ),
    );
  });

  test('getFileResponseForUrl propagates the typed DioException', () async {
    await expectLater(
      request.getFileResponseForUrl('http://127.0.0.1/anything'),
      throwsA(
        isA<DioException>().having(
          (e) => e.type,
          'type',
          DioExceptionType.badResponse,
        ),
      ),
    );
  });

  test('checkForUpdate includes HTTP status and response body', () async {
    final interceptor = InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.reject(
          DioException(
            requestOptions: options,
            response: Response<String>(
              requestOptions: options,
              statusCode: 403,
              data: 'rate limited',
            ),
            type: DioExceptionType.badResponse,
          ),
        );
      },
    );
    request.dio.interceptors.add(interceptor);
    addTearDown(() {
      request.dio.interceptors.remove(interceptor);
    });

    await expectLater(
      request.checkForUpdate(),
      throwsA(
        isA<MessageException>()
            .having((e) => e.message, 'message', contains('[403]'))
            .having((e) => e.message, 'message', contains('rate limited')),
      ),
    );
  });

  test('every IP lookup service is asked over HTTPS', () {
    expect(request.ipInfoSourceUrls, isNotEmpty);
    for (final url in request.ipInfoSourceUrls) {
      expect(Uri.parse(url).scheme, 'https', reason: url);
    }
  });

  test('the Play build never asks GitHub for a newer release', () async {
    var requests = 0;
    final interceptor = InterceptorsWrapper(
      onRequest: (options, handler) {
        requests++;
        handler.reject(DioException(requestOptions: options));
      },
    );
    request.dio.interceptors.add(interceptor);
    debugSelfUpdateEnabled = false;
    addTearDown(() {
      debugSelfUpdateEnabled = null;
      request.dio.interceptors.remove(interceptor);
    });

    await expectLater(request.checkForUpdate(), completion(isNull));
    expect(requests, 0);
  });
}
