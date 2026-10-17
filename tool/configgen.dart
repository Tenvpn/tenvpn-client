import 'dart:io';

import 'package:args/args.dart';
import 'package:fl_clash/tenvpn/configgen/configgen.dart';

// dart run tool/configgen.dart -s subscription.yaml [-a awg.conf] [-o out.yaml]
void main(List<String> arguments) {
  final parser = ArgParser()
    ..addOption('subscription', abbr: 's', mandatory: true)
    ..addOption('awg', abbr: 'a')
    ..addOption('out', abbr: 'o')
    ..addFlag('no-tun', negatable: false)
    ..addFlag('awg-first', negatable: false);
  final args = parser.parse(arguments);
  final awgPath = args.option('awg');
  try {
    final generated = generateFromSubscription(
      File(args.option('subscription')!).readAsStringSync(),
      awg: awgPath == null ? null : parseAwgConf(File(awgPath).readAsStringSync()),
      options: ConfigGenOptions(
        tun: !args.flag('no-tun'),
        autoStrategy: args.flag('awg-first')
            ? AutoStrategy.awgFirst
            : AutoStrategy.fastest,
      ),
    );
    final text = encodeConfig(generated);
    final out = args.option('out');
    if (out == null) {
      stdout.write(text);
    } else {
      File(out).writeAsStringSync(text);
      stderr.writeln('${generated.servers.length} servers → $out');
    }
  } on ConfigGenException catch (e) {
    stderr.writeln(e);
    exitCode = 1;
  }
}
