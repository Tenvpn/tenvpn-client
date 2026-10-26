import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

import 'expiry.dart';
import 'presentation.dart';

enum SubscriptionIssueKind { unreachable, removed, expired, invalid }

class SubscriptionIssue {
  final SubscriptionIssueKind kind;
  final int? code;

  const SubscriptionIssue(this.kind, [this.code]);

  /// The servers of a removed or ended subscription are dead for sure: the
  /// main screen hides them instead of showing «нет ответа» everywhere.
  bool get hidesServers =>
      kind == SubscriptionIssueKind.removed ||
      kind == SubscriptionIssueKind.expired;

  @override
  bool operator ==(Object other) =>
      other is SubscriptionIssue && other.kind == kind && other.code == code;

  @override
  int get hashCode => Object.hash(kind, code);
}

const _removedStatuses = {401, 403, 404, 410};

SubscriptionIssue classifySubscriptionError(Object error) {
  if (error is DioException) {
    final status = error.response?.statusCode;
    if (error.type == DioExceptionType.badResponse && status != null) {
      return SubscriptionIssue(
        _removedStatuses.contains(status)
            ? SubscriptionIssueKind.removed
            : SubscriptionIssueKind.unreachable,
        status,
      );
    }
    return const SubscriptionIssue(SubscriptionIssueKind.unreachable);
  }
  if (error is SocketException || error is TimeoutException) {
    return const SubscriptionIssue(SubscriptionIssueKind.unreachable);
  }
  return const SubscriptionIssue(SubscriptionIssueKind.invalid);
}

/// A failed download says why; otherwise an ended or suspended plan counts.
SubscriptionIssue? subscriptionIssue({
  SubscriptionIssue? lastError,
  required TenvpnExpiry expiry,
  required DateTime now,
}) {
  if (lastError != null) return lastError;
  final date = expiry.date;
  if (expiry.suspended || (date != null && daysLeft(date, now) < 0)) {
    return const SubscriptionIssue(SubscriptionIssueKind.expired);
  }
  return null;
}
