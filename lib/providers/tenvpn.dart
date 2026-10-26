import 'package:fl_clash/tenvpn/subscription_issue.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Why the last download of each profile failed, until one works.
class TenvpnUpdateErrors extends Notifier<Map<int, SubscriptionIssue>> {
  @override
  Map<int, SubscriptionIssue> build() => const {};

  void record(int profileId, Object error) {
    state = {...state, profileId: classifySubscriptionError(error)};
  }

  void clear(int profileId) {
    if (!state.containsKey(profileId)) return;
    state = {...state}..remove(profileId);
  }
}

final tenvpnUpdateErrorsProvider =
    NotifierProvider<TenvpnUpdateErrors, Map<int, SubscriptionIssue>>(
      TenvpnUpdateErrors.new,
    );
