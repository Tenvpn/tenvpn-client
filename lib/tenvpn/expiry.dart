import 'account.dart';
import 'presentation.dart';
import 'tenvpn_state.dart';

const expiryNoticeDays = 2;

enum ExpirySource { account, subscription }

class TenvpnExpiry {
  final DateTime? date;
  final ExpirySource source;
  final AccountInfo? account;

  const TenvpnExpiry({this.date, required this.source, this.account});

  bool get suspended => account?.status == AccountStatus.suspended;

  bool get free => account?.status == AccountStatus.free;
}

/// The backend account wins: the panel knows only an end date.
TenvpnExpiry resolveExpiry({AccountCache? account, DateTime? subscription}) {
  if (account != null) {
    return TenvpnExpiry(
      date: account.account.status == AccountStatus.free
          ? null
          : account.expiry,
      source: ExpirySource.account,
      account: account.account,
    );
  }
  return TenvpnExpiry(date: subscription, source: ExpirySource.subscription);
}

/// One notice per paid-until date: a top-up moves the date and re-arms it.
String? expiryNoticeKey(
  TenvpnExpiry expiry,
  DateTime now, {
  String? alreadyShown,
}) {
  final date = expiry.date;
  if (date == null || expiry.free) return null;
  final left = daysLeft(date, now);
  if (left > expiryNoticeDays) return null;
  final key = date.toIso8601String().substring(0, 10);
  return key == alreadyShown ? null : key;
}
