import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/tenvpn/tenvpn.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'main_view.dart' show tenvpnContentWidth;
import 'state.dart';
import 'theme.dart';

/// Nothing leaves the phone by itself: the person reads the cleaned text and
/// sends it to support with the system share sheet.
class TenvpnReportView extends ConsumerStatefulWidget {
  final Future<List<ConnectivityResult>> Function()? connectivity;

  const TenvpnReportView({super.key, this.connectivity});

  @override
  ConsumerState<TenvpnReportView> createState() => _TenvpnReportViewState();
}

class _TenvpnReportViewState extends ConsumerState<TenvpnReportView> {
  String? _report;

  @override
  void initState() {
    super.initState();
    unawaited(_build());
  }

  Future<String> _network() async {
    final check =
        widget.connectivity ?? () => Connectivity().checkConnectivity();
    final kinds = await check().catchError((_) => <ConnectivityResult>[]);
    final groups = ref.read(groupsProvider);
    final tier = groups.getGroup(autoGroupName)?.now;
    return [
      kinds.map((k) => k.name).join('+'),
      if (ref.read(isStartProvider)) 'VPN on' else 'VPN off',
      if (tier != null && autoTierGroupNames.contains(tier)) tier,
      if (ref.read(appSettingProvider).tenvpnRussianDirect) 'RU direct',
    ].where((part) => part.isNotEmpty).join(' · ');
  }

  Future<void> _build() async {
    final selection = ref.read(tenvpnSelectionProvider);
    final setting = ref.read(appSettingProvider);
    final theme = ref.read(themeSettingProvider);
    final report = buildSupportReport(
      version: globalState.packageInfo.version,
      platform: Platform.operatingSystem,
      os: Platform.operatingSystemVersion,
      network: await _network(),
      server: [
        if (selection.auto) autoGroupName,
        ?selection.server,
      ].join(' · '),
      look: '${setting.look.name}, ${theme.themeMode.name}',
      logs: [
        for (final log in ref.read(logsProvider).list)
          '${log.dateTime} ${log.logLevel.name} ${log.payload}',
      ],
      now: DateTime.now(),
    );
    if (mounted) setState(() => _report = report);
  }

  Future<void> _share() async {
    final report = _report;
    if (report == null) return;
    if (await app?.shareText(report) ?? false) return;
    await _copy();
  }

  Future<void> _copy() async {
    final report = _report;
    if (report == null) return;
    await Clipboard.setData(ClipboardData(text: report));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(context.appLocalizations.copySuccess)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final p = context.palette;
    final report = _report;
    return Scaffold(
      appBar: AppBar(title: Text(l.tenvpnReportTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: tenvpnContentWidth),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    l.tenvpnReportNote,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.45,
                      color: p.muted,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: TenvpnCard(
                      padding: const EdgeInsets.all(12),
                      child: report == null
                          ? const Center(child: CircularProgressIndicator())
                          : SingleChildScrollView(
                              child: SelectableText(
                                report,
                                key: const ValueKey('tenvpn-report-text'),
                                style: TextStyle(
                                  fontFamily: 'JetBrainsMono',
                                  fontSize: 11.5,
                                  height: 1.4,
                                  color: p.text,
                                ),
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TenvpnBigButton(
                    key: const ValueKey('tenvpn-report-share'),
                    label: system.isAndroid ? l.tenvpnShare : l.copy,
                    height: 54,
                    onPressed: report == null ? null : _share,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TenvpnBigButton(
                          key: const ValueKey('tenvpn-report-copy'),
                          label: l.copy,
                          primary: false,
                          height: 48,
                          onPressed: report == null ? null : _copy,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TenvpnBigButton(
                          key: const ValueKey('tenvpn-report-support'),
                          label: l.tenvpnOpenSupport,
                          primary: false,
                          height: 48,
                          onPressed: () => unawaited(
                            launchUrl(
                              Uri.parse(tenvpnSupportUrl),
                              mode: LaunchMode.externalApplication,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
