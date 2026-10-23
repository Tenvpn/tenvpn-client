import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/state.dart';

import 'account.dart';
import 'awg_source.dart';
import 'configgen/builder.dart';
import 'tenvpn_config.dart';
import 'tenvpn_state.dart';

export 'account.dart';
export 'awg_source.dart';
export 'expiry.dart';
export 'telemetry.dart';
export 'headers.dart';
export 'network_mode.dart';
export 'configgen/configgen.dart';
export 'presentation.dart';
export 'support.dart';
export 'tenvpn_config.dart';
export 'tenvpn_state.dart';

final tenvpnConfig = TenvpnConfigService(
  store: TenvpnStateStore(() => appPath.tenvpnStatePath),
  transport: (uri, headers) async {
    final response = await request.getTextResponseAnyStatus(
      uri.toString(),
      headers: headers,
    );
    return AwgHttpResponse(response.statusCode ?? 0, response.data ?? '');
  },
  endpoints: TenvpnEndpoints.configured,
  options: () {
    final settings = globalState.container.read(appSettingProvider);
    return ConfigGenOptions(
      autoStrategy: settings.awgPriority
          ? AutoStrategy.awgFirst
          : AutoStrategy.fastest,
      russianDirect: settings.tenvpnRussianDirect,
    );
  },
  log: (message) => commonPrint.log(message, logLevel: LogLevel.warning),
);

Future<AwgHttpResponse> tenvpnPost(
  Uri uri,
  Map<String, String> headers,
  String body,
) async {
  final response = await request.postTextAnyStatus(
    uri.toString(),
    body: body,
    headers: headers,
  );
  return AwgHttpResponse(response.statusCode ?? 0, response.data ?? '');
}
