import 'dart:io';

import 'package:dio/dio.dart';
import 'package:fl_clash/providers/tenvpn.dart';
import 'package:fl_clash/tenvpn/configgen/errors.dart';
import 'package:fl_clash/tenvpn/expiry.dart';
import 'package:fl_clash/tenvpn/subscription_issue.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

DioException _status(int code) => DioException(
  requestOptions: RequestOptions(path: '/sub'),
  type: DioExceptionType.badResponse,
  response: Response(
    requestOptions: RequestOptions(path: '/sub'),
    statusCode: code,
  ),
);

void main() {
  test('download errors say what happened to the subscription', () {
    SubscriptionIssue of(Object error) => classifySubscriptionError(error);
    expect(
      of(_status(404)),
      const SubscriptionIssue(SubscriptionIssueKind.removed, 404),
    );
    expect(of(_status(410)).hidesServers, isTrue);
    expect(
      of(_status(502)),
      const SubscriptionIssue(SubscriptionIssueKind.unreachable, 502),
    );
    expect(of(_status(502)).hidesServers, isFalse);
    expect(
      of(
        DioException(
          requestOptions: RequestOptions(path: '/'),
          type: DioExceptionType.connectionTimeout,
        ),
      ).kind,
      SubscriptionIssueKind.unreachable,
    );
    expect(
      of(const SocketException('no route')).kind,
      SubscriptionIssueKind.unreachable,
    );
    expect(
      of(const ConfigGenException(ConfigGenErrorCode.shareLinks)).kind,
      SubscriptionIssueKind.invalid,
    );
    expect(of(_status(404)).hashCode, of(_status(404)).hashCode);
  });

  test('an ended or suspended plan counts when the download is fine', () {
    final now = DateTime(2026, 10, 26);
    expect(
      subscriptionIssue(
        expiry: TenvpnExpiry(
          date: DateTime(2026, 10, 25),
          source: ExpirySource.subscription,
        ),
        now: now,
      )?.kind,
      SubscriptionIssueKind.expired,
    );
    expect(
      subscriptionIssue(
        expiry: TenvpnExpiry(
          date: DateTime(2026, 11, 2),
          source: ExpirySource.subscription,
        ),
        now: now,
      ),
      isNull,
    );
    expect(
      subscriptionIssue(
        lastError: const SubscriptionIssue(SubscriptionIssueKind.invalid),
        expiry: const TenvpnExpiry(source: ExpirySource.subscription),
        now: now,
      )?.kind,
      SubscriptionIssueKind.invalid,
    );
  });

  test('the error store records per profile and clears on success', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final errors = container.read(tenvpnUpdateErrorsProvider.notifier);
    errors.record(3, _status(404));
    expect(container.read(tenvpnUpdateErrorsProvider)[3]?.code, 404);
    errors.clear(4);
    errors.clear(3);
    expect(container.read(tenvpnUpdateErrorsProvider), isEmpty);
  });
}
