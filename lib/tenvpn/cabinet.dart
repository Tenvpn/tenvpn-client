import 'dart:convert';

import 'account.dart';
import 'telemetry.dart';

/// A one-time link that opens the web cabinet already signed in as the owner
/// of the device token (`docs/api.md` §8). Only an https link on the API's
/// own host is accepted; anything else falls back to the cabinet's login.
Future<String?> fetchCabinetLink(
  TenvpnEndpoints endpoints,
  String token,
  TenvpnPost post,
) async {
  try {
    final response = await post(Uri.parse(endpoints.cabinetLink), {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    }, '{}');
    if (response.statusCode != 200) return null;
    final body = json.decode(response.body);
    final url = body is Map ? safeHttpsUrl(body['url']) : null;
    if (url == null) return null;
    return Uri.parse(url).host == Uri.parse(endpoints.base).host ? url : null;
  } catch (_) {
    return null;
  }
}

/// Where «Кабинет» goes: the signed-in link when the backend gives one,
/// the cabinet's own page otherwise, the bot when there is no backend.
Future<String> cabinetUrl({
  required TenvpnEndpoints? endpoints,
  required String? token,
  required String fallback,
  required TenvpnPost post,
}) async {
  if (endpoints == null) return fallback;
  if (token != null) {
    final link = await fetchCabinetLink(endpoints, token, post);
    if (link != null) return link;
  }
  return endpoints.cabinet;
}
