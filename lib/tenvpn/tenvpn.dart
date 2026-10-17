import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/state.dart';

import 'awg_source.dart';
import 'configgen/builder.dart';
import 'tenvpn_config.dart';
import 'tenvpn_state.dart';

export 'awg_source.dart';
export 'headers.dart';
export 'configgen/configgen.dart';
export 'presentation.dart';
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
  options: () => ConfigGenOptions(
    autoStrategy: globalState.container.read(appSettingProvider).awgPriority
        ? AutoStrategy.awgFirst
        : AutoStrategy.fastest,
  ),
  log: (message) => commonPrint.log(message, logLevel: LogLevel.warning),
);
