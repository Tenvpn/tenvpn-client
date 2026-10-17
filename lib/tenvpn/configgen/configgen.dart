import 'package:fl_clash/common/yaml.dart';

import 'builder.dart';
import 'subscription.dart';

export 'awg.dart';
export 'builder.dart';
export 'constants.dart';
export 'errors.dart';
export 'subscription.dart';

GeneratedConfig generateFromSubscription(
  String subscription, {
  Map<String, dynamic>? awg,
  ConfigGenOptions options = const ConfigGenOptions(),
}) {
  return buildConfig(
    parseSubscription(subscription),
    awg: awg,
    options: options,
  );
}

String encodeConfig(GeneratedConfig generated) => yaml.encode(generated.config);
