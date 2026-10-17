import 'dart:convert';

import 'account.dart';
import 'awg_source.dart';
import 'configgen/subscription.dart';

typedef TenvpnPost =
    Future<AwgHttpResponse> Function(
      Uri uri,
      Map<String, String> headers,
      String body,
    );

/// Everything telemetry ever sends: no IP, no server name, no traffic, no
/// sites. `docs/privacy.md` lists the same fields; keep them in step.
class ConnectEvent {
  final String appVersion;
  final String platform;
  final String osVersion;
  final String protocol;

  const ConnectEvent({
    required this.appVersion,
    required this.platform,
    required this.osVersion,
    required this.protocol,
  });

  Map<String, dynamic> toJson() => {
    'version': 1,
    'event': 'connected',
    'app_version': appVersion,
    'platform': platform,
    'os_version': osVersion,
    'protocol': protocol,
  };
}

String connectionProtocol(ServerEntry? entry) {
  if (entry == null) return 'unknown';
  return switch (entry.type) {
    'wireguard' => entry.security == 'amnezia' ? 'amneziawg' : 'wireguard',
    'vless' => switch ((entry.network, entry.security)) {
      (null, 'reality') => 'vless-reality',
      (null, _) => 'vless-tcp',
      (final network?, _) => 'vless-$network',
    },
    final type => type,
  };
}

class TelemetryThrottle {
  final Duration window;
  final DateTime Function() now;
  final _sent = <String, DateTime>{};

  TelemetryThrottle({
    this.window = const Duration(minutes: 30),
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  bool allow(String protocol) {
    final last = _sent[protocol];
    final current = now();
    if (last != null && current.difference(last) < window) return false;
    _sent[protocol] = current;
    return true;
  }
}

Future<bool> sendConnectEvent(
  TenvpnEndpoints endpoints,
  String token,
  ConnectEvent event,
  TenvpnPost post,
) async {
  try {
    final response = await post(Uri.parse(endpoints.telemetry), {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    }, json.encode(event.toJson()));
    return response.statusCode >= 200 && response.statusCode < 300;
  } catch (_) {
    return false;
  }
}
