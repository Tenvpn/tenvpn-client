import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import 'print.dart';
import 'protocol.dart';

typedef InstallConfigCallBack = void Function(String url);
typedef InstallTenvpnCallBack =
    void Function(String url, String awgUrl, String awgToken);

class LinkManager {
  static LinkManager? _instance;
  StreamSubscription? subscription;
  Uri? _pendingUri;

  LinkManager._internal();

  @visibleForTesting
  Stream<Uri> Function() uriLinkStream = () => AppLinks().uriLinkStream;

  /// Linux argv: the gtk plugin hooks GApplication too late to see it.
  void seedInitialLink(List<String> args) {
    for (final arg in args) {
      final uri = Uri.tryParse(arg);
      if (uri != null && protocolSchemes.contains(uri.scheme)) {
        _pendingUri = uri;
        return;
      }
    }
  }

  Future<void> initAppLinksListen(
    Function(String url) installConfigCallBack, {
    InstallTenvpnCallBack? installTenvpnCallBack,
  }) async {
    commonPrint.log('initAppLinksListen');
    destroy();
    subscription = uriLinkStream().listen((uri) {
      _handle(uri, installConfigCallBack, installTenvpnCallBack);
    });
    final pending = _pendingUri;
    _pendingUri = null;
    if (pending != null) {
      _handle(pending, installConfigCallBack, installTenvpnCallBack);
    }
  }

  void _handle(
    Uri uri,
    Function(String url) installConfigCallBack,
    InstallTenvpnCallBack? installTenvpnCallBack,
  ) {
    commonPrint.log('onAppLink: ${uri.scheme}://${uri.host}');
    if (uri.host == 'install-config') {
      final parameters = uri.queryParameters;
      final url = parameters['url'];
      if (url == null) return;
      final awgUrl = parameters['awg'];
      final awgToken = parameters['awg_token'];
      if (installTenvpnCallBack != null &&
          awgUrl != null &&
          awgToken != null &&
          awgToken.isNotEmpty) {
        installTenvpnCallBack(url, awgUrl, awgToken);
      } else {
        installConfigCallBack(url);
      }
    }
  }

  void destroy() {
    if (subscription != null) {
      subscription?.cancel();
      subscription = null;
    }
  }

  factory LinkManager() {
    _instance ??= LinkManager._internal();
    return _instance!;
  }
}

final linkManager = LinkManager();
