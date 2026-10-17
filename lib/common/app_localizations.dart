import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:fl_clash/core/desktop/launch_policy.dart';
import 'package:fl_clash/core/method.dart';
import 'package:fl_clash/l10n/l10n.dart';

import 'dart:ui';

final currentAppLocalizations = AppLocalizations.current;

String? networkErrorMessage(Object error, AppLocalizations appLocalizations) {
  if (error case CoreMethodException(:final code, :final message)) {
    final summary = switch (code) {
      'request_bad_response' => appLocalizations.networkException,
      'request_error' => appLocalizations.unknownNetworkError,
      _ => null,
    };
    return summary == null ? null : _withNetworkDetail(summary, message);
  }
  if (error is DioException) {
    if (error.type == DioExceptionType.badResponse) {
      final response = error.response;
      final statusCode = response?.statusCode;
      final summary = statusCode == null
          ? appLocalizations.networkException
          : '${appLocalizations.networkException} [$statusCode]';
      final data = response?.data;
      final String body;
      if (data is Uint8List) {
        try {
          body = utf8.decode(data);
        } on FormatException {
          return summary;
        }
      } else if (data is Map || data is List) {
        body = jsonEncode(data);
      } else {
        body = data?.toString() ?? '';
      }
      return _withNetworkDetail(summary, body);
    }
    final detail = error.error?.toString().trim();
    return _withNetworkDetail(
      appLocalizations.unknownNetworkError,
      detail?.isNotEmpty == true ? detail : error.message,
    );
  }
  return null;
}

String _withNetworkDetail(String summary, String? detail) {
  final text = detail?.trim() ?? '';
  return text.isEmpty ? summary : '$summary\n$text';
}

String? coreLaunchBlockedMessage(
  Object error,
  AppLocalizations appLocalizations,
) {
  if (!isPolicyBlockedLaunch(error)) {
    return null;
  }
  return switch (smartAppControlStateReader()) {
    SmartAppControlState.on || SmartAppControlState.evaluation =>
      appLocalizations.coreBlockedBySmartAppControlTip,
    _ => appLocalizations.coreBlockedByPolicyTip(launchOsError(error)!),
  };
}

String userFacingErrorMessage(Object error, AppLocalizations appLocalizations) {
  return networkErrorMessage(error, appLocalizations) ??
      coreLaunchBlockedMessage(error, appLocalizations) ??
      switch (error) {
        CoreMethodException(:final message) => message,
        _ => error.toString(),
      };
}

/// TENVPN speaks Russian unless the user picks another language, whatever
/// the phone's system language is.
const appDefaultLocale = Locale('ru');

Locale? getLocaleForString(String? localString) {
  if (localString == null) return null;
  final localSplit = localString.split('_');
  if (localSplit.length == 1) {
    return Locale(localSplit[0]);
  }
  if (localSplit.length == 2) {
    return Locale(localSplit[0], localSplit[1]);
  }
  if (localSplit.length == 3) {
    return Locale.fromSubtags(
      languageCode: localSplit[0],
      scriptCode: localSplit[1],
      countryCode: localSplit[2],
    );
  }
  return null;
}

String importErrorMessage(Object error, AppLocalizations appLocalizations) {
  if (error is DioException && error.type == DioExceptionType.badResponse) {
    return appLocalizations.tenvpnImportDeadLink;
  }
  if (error is DioException ||
      error is TimeoutException ||
      error is SocketException) {
    return appLocalizations.tenvpnImportOffline;
  }
  return userFacingErrorMessage(error, appLocalizations);
}
