import 'dart:convert';

class AwgSource {
  final String url;
  final String token;

  const AwgSource({required this.url, required this.token});

  factory AwgSource.fromJson(Map<String, dynamic> json) =>
      AwgSource(url: json['url'] as String, token: json['token'] as String);

  Map<String, dynamic> toJson() => {'url': url, 'token': token};
}

class AwgHttpResponse {
  final int statusCode;
  final String body;

  const AwgHttpResponse(this.statusCode, this.body);
}

typedef AwgTransport =
    Future<AwgHttpResponse> Function(Uri uri, Map<String, String> headers);

sealed class AwgFetchResult {
  const AwgFetchResult();
}

final class AwgFetched extends AwgFetchResult {
  final String conf;
  final String? name;

  const AwgFetched({required this.conf, this.name});
}

/// The backend says this user or device has no AmneziaWG (any more): the
/// cached profile must go too, or a revoked peer would keep being dialled.
final class AwgRevoked extends AwgFetchResult {
  final int statusCode;

  const AwgRevoked(this.statusCode);
}

final class AwgUnavailable extends AwgFetchResult {
  final String reason;

  const AwgUnavailable(this.reason);
}

const _revokedStatuses = {401, 403, 404, 410};

Future<AwgFetchResult> fetchAwg(
  AwgSource source,
  AwgTransport transport,
) async {
  final uri = Uri.tryParse(source.url);
  if (uri == null || !uri.hasScheme) {
    return const AwgUnavailable('bad url');
  }
  final AwgHttpResponse response;
  try {
    response = await transport(uri, {
      'Authorization': 'Bearer ${source.token}',
      'Accept': 'application/json',
    });
  } catch (e) {
    return AwgUnavailable(e.runtimeType.toString());
  }
  if (_revokedStatuses.contains(response.statusCode)) {
    return AwgRevoked(response.statusCode);
  }
  if (response.statusCode != 200) {
    return AwgUnavailable('HTTP ${response.statusCode}');
  }
  try {
    final body = json.decode(response.body);
    if (body is! Map || body['version'] != 1 || body['conf'] is! String) {
      return const AwgUnavailable('unexpected body');
    }
    final name = body['name'];
    return AwgFetched(
      conf: body['conf'] as String,
      name: name is String && name.trim().isNotEmpty ? name.trim() : null,
    );
  } on FormatException {
    return const AwgUnavailable('body is not JSON');
  }
}
