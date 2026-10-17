import 'dart:convert';

import 'awg_source.dart';

const tenvpnApiBase = String.fromEnvironment('TENVPN_API_BASE');
const tenvpnBotUrl = 'https://t.me/Tenvpnrobot?start=src_app';

class TenvpnEndpoints {
  final String base;

  const TenvpnEndpoints(this.base);

  static TenvpnEndpoints? get configured => fromBase(tenvpnApiBase);

  static TenvpnEndpoints? fromBase(String base) {
    final uri = Uri.tryParse(base.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    final clean = base.trim();
    return TenvpnEndpoints(
      clean.endsWith('/') ? clean.substring(0, clean.length - 1) : clean,
    );
  }

  String get awg => '$base/api/app/v1/awg';

  String get account => '$base/api/app/v1/account';

  String get telemetry => '$base/api/app/v1/telemetry';
}

enum AccountStatus { active, suspended, free }

class AccountInfo {
  final double balanceRub;
  final double dailyRateRub;
  final int daysLeft;
  final DateTime? paidUntil;
  final int activeDevices;
  final AccountStatus status;
  final String? renewUrl;
  final String? supportUrl;

  const AccountInfo({
    required this.balanceRub,
    required this.dailyRateRub,
    required this.daysLeft,
    this.paidUntil,
    required this.activeDevices,
    this.status = AccountStatus.active,
    this.renewUrl,
    this.supportUrl,
  });

  /// Throws [FormatException] on a body that does not follow `docs/api.md`.
  factory AccountInfo.fromJson(Map<String, dynamic> json) {
    num number(String key) {
      final value = json[key];
      if (value is num) return value;
      throw FormatException('$key is missing');
    }

    final devices = json['devices'];
    final paidUntil = json['paid_until'];
    return AccountInfo(
      balanceRub: number('balance_rub').toDouble(),
      dailyRateRub: number('daily_rate_rub').toDouble(),
      daysLeft: number('days_left').toInt(),
      paidUntil: paidUntil is String ? DateTime.tryParse(paidUntil) : null,
      activeDevices: devices is Map && devices['active'] is int
          ? devices['active'] as int
          : 0,
      status: AccountStatus.values.firstWhere(
        (status) => status.name == json['status'],
        orElse: () => AccountStatus.active,
      ),
      renewUrl: safeHttpsUrl(json['renew_url']),
      supportUrl: safeHttpsUrl(json['support_url']),
    );
  }

  Map<String, dynamic> toJson() => {
    'version': 1,
    'balance_rub': balanceRub,
    'daily_rate_rub': dailyRateRub,
    'days_left': daysLeft,
    'paid_until': ?paidUntil?.toIso8601String().substring(0, 10),
    'devices': {'active': activeDevices},
    'status': status.name,
    'renew_url': ?renewUrl,
    'support_url': ?supportUrl,
  };

  /// The last day that is paid for: `paid_until` when sent, otherwise counted
  /// from `days_left` as of [fetchedAt].
  DateTime expiry(DateTime fetchedAt) {
    final sent = paidUntil;
    if (sent != null) return DateTime(sent.year, sent.month, sent.day);
    final day = DateTime(fetchedAt.year, fetchedAt.month, fetchedAt.day);
    return day.add(Duration(days: daysLeft));
  }
}

String? safeHttpsUrl(Object? value) {
  if (value is! String) return null;
  final uri = Uri.tryParse(value.trim());
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) return null;
  return uri.toString();
}

sealed class AccountFetchResult {
  const AccountFetchResult();
}

final class AccountFetched extends AccountFetchResult {
  final AccountInfo account;

  const AccountFetched(this.account);
}

final class AccountRevoked extends AccountFetchResult {
  final int statusCode;

  const AccountRevoked(this.statusCode);
}

final class AccountUnavailable extends AccountFetchResult {
  final String reason;

  const AccountUnavailable(this.reason);
}

const _revokedStatuses = {401, 403, 410};

Future<AccountFetchResult> fetchAccount(
  TenvpnEndpoints endpoints,
  String token,
  AwgTransport transport,
) async {
  final AwgHttpResponse response;
  try {
    response = await transport(Uri.parse(endpoints.account), {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
    });
  } catch (e) {
    return AccountUnavailable(e.runtimeType.toString());
  }
  if (_revokedStatuses.contains(response.statusCode)) {
    return AccountRevoked(response.statusCode);
  }
  if (response.statusCode != 200) {
    return AccountUnavailable('HTTP ${response.statusCode}');
  }
  try {
    final body = json.decode(response.body);
    if (body is! Map<String, dynamic> || body['version'] != 1) {
      return const AccountUnavailable('unexpected body');
    }
    return AccountFetched(AccountInfo.fromJson(body));
  } on FormatException catch (e) {
    return AccountUnavailable(e.message);
  }
}
