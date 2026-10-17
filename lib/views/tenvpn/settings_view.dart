import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/views/about.dart';
import 'package:fl_clash/views/access.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'advanced_view.dart';
import 'main_view.dart';
import 'mascot.dart';
import 'onboarding_view.dart';
import 'privacy_view.dart';
import 'state.dart';
import 'theme.dart';

class TenvpnSettingsView extends ConsumerWidget {
  const TenvpnSettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.appLocalizations;
    final hasAwg = ref.watch(tenvpnHasAwgProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.tenvpnSettings)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: tenvpnContentWidth),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              4,
              16,
              24 + MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              const _SettingsHeader(),
              TenvpnSettingsGroup(
                title: l.tenvpnSectionConnection,
                children: [
                  const _AutoConnectRow(),
                  if (system.isDesktop) const _AutoStartRow(),
                  if (system.isAndroid)
                    TenvpnSettingsRow(
                      icon: Symbols.restart_alt,
                      title: l.tenvpnAlwaysOn,
                      subtitle: l.tenvpnAlwaysOnDesc,
                      onTap: () => unawaited(app?.openVpnSettings()),
                      trailing: const Icon(Symbols.open_in_new, size: 20),
                    ),
                  if (system.isAndroid)
                    TenvpnSettingsRow(
                      icon: Symbols.call_split,
                      title: l.tenvpnSplitTunnel,
                      subtitle: l.tenvpnSplitTunnelDesc,
                      onTap: () =>
                          BaseNavigator.push(context, const AccessView()),
                    ),
                  if (hasAwg || system.isWindows) const _ProtocolRow(),
                ],
              ),
              TenvpnSettingsGroup(
                title: l.tenvpnSectionSubscription,
                children: [
                  const _RefreshRow(),
                  TenvpnSettingsRow(
                    icon: Symbols.link,
                    title: l.tenvpnChangeLink,
                    onTap: () => BaseNavigator.push(
                      context,
                      const TenvpnOnboardingView(replace: true),
                    ),
                  ),
                ],
              ),
              TenvpnSettingsGroup(
                title: l.tenvpnSectionLook,
                children: const [
                  _ThemeRow(),
                  _LanguageRow(),
                  _ListStyleRow(),
                  _SortRow(),
                ],
              ),
              TenvpnSettingsGroup(
                title: l.other,
                children: [
                  TenvpnSettingsRow(
                    icon: Symbols.tune,
                    title: l.tenvpnAdvanced,
                    subtitle: l.tenvpnAdvancedDesc,
                    onTap: () =>
                        BaseNavigator.push(context, const TenvpnAdvancedView()),
                  ),
                  const _TelemetryRow(),
                  TenvpnSettingsRow(
                    icon: Symbols.shield_lock,
                    title: l.tenvpnPrivacy,
                    onTap: () =>
                        BaseNavigator.push(context, const TenvpnPrivacyView()),
                  ),
                  TenvpnSettingsRow(
                    icon: Symbols.info,
                    title: l.tenvpnAbout,
                    subtitle: l.tenvpnVersion(globalState.packageInfo.version),
                    onTap: () => BaseNavigator.push(context, const AboutView()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TenvpnSettingsGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const TenvpnSettingsGroup({
    super.key,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: p.muted,
              ),
            ),
          ),
          TenvpnCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) Divider(height: 1, indent: 56, color: p.border),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TenvpnSettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const TenvpnSettingsRow({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ListTile(
      onTap: onTap,
      minVerticalPadding: 12,
      leading: Icon(icon, color: p.cocoaText),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 15.5,
          fontWeight: FontWeight.w500,
          color: p.text,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!, style: TextStyle(fontSize: 13, color: p.muted)),
      trailing:
          trailing ??
          (onTap == null
              ? null
              : Icon(Symbols.chevron_right, color: p.mutedDeep)),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TenvpnSettingsRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: () => onChanged(!value),
      trailing: Switch(value: value, onChanged: onChanged),
    );
  }
}

class _AutoConnectRow extends ConsumerWidget {
  const _AutoConnectRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.appLocalizations;
    final value = ref.watch(appSettingProvider.select((s) => s.autoRun));
    return _SwitchRow(
      icon: Symbols.bolt,
      title: l.tenvpnAutoConnect,
      subtitle: l.tenvpnAutoConnectDesc,
      value: value,
      onChanged: (value) => ref
          .read(appSettingProvider.notifier)
          .update((s) => s.copyWith(autoRun: value)),
    );
  }
}

class _TelemetryRow extends ConsumerWidget {
  const _TelemetryRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.appLocalizations;
    final value = ref.watch(
      appSettingProvider.select((s) => s.tenvpnTelemetry),
    );
    return _SwitchRow(
      icon: Symbols.monitoring,
      title: l.tenvpnTelemetry,
      subtitle: l.tenvpnTelemetryDesc,
      value: value,
      onChanged: (value) => ref
          .read(appSettingProvider.notifier)
          .update((s) => s.copyWith(tenvpnTelemetry: value)),
    );
  }
}

class _AutoStartRow extends ConsumerWidget {
  const _AutoStartRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.appLocalizations;
    final value = ref.watch(appSettingProvider.select((s) => s.autoLaunch));
    return _SwitchRow(
      icon: Symbols.restart_alt,
      title: l.tenvpnAutoStart,
      subtitle: l.tenvpnAutoStartDesc,
      value: value,
      onChanged: (value) => ref
          .read(appSettingProvider.notifier)
          .update(
            (s) => s.copyWith(
              autoLaunch: value,
              highPriorityAutoLaunch: value ? s.highPriorityAutoLaunch : false,
            ),
          ),
    );
  }
}

class _ProtocolRow extends ConsumerWidget {
  const _ProtocolRow();

  Future<void> _set(WidgetRef ref, bool awgFirst) async {
    final current = ref.read(appSettingProvider).awgPriority;
    if (current == awgFirst) return;
    ref
        .read(appSettingProvider.notifier)
        .update((s) => s.copyWith(awgPriority: awgFirst));
    final profile = ref.read(currentProfileProvider);
    if (profile == null) return;
    await globalState.safeRun(
      () => ref
          .read(profilesActionProvider.notifier)
          .updateProfile(profile, showLoading: true),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.appLocalizations;
    final p = context.palette;
    final awgFirst = ref.watch(appSettingProvider.select((s) => s.awgPriority));
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Symbols.swap_horiz, color: p.cocoaText),
              const SizedBox(width: 16),
              Text(
                l.tenvpnProtocol,
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w500,
                  color: p.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              key: const ValueKey('tenvpn-protocol'),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: false, label: Text(l.tenvpnProtocolAuto)),
                ButtonSegment(value: true, label: Text(l.tenvpnProtocolAwg)),
              ],
              selected: {awgFirst},
              onSelectionChanged: (value) => _set(ref, value.first),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            awgFirst ? l.tenvpnProtocolAwgDesc : l.tenvpnProtocolAutoDesc,
            style: TextStyle(fontSize: 13, color: p.muted),
          ),
        ],
      ),
    );
  }
}

class _RefreshRow extends ConsumerWidget {
  const _RefreshRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.appLocalizations;
    final profile = ref.watch(currentProfileProvider);
    final updating = profile == null
        ? false
        : ref.watch(isUpdatingProvider(profile.updatingKey));
    final updated = profile?.lastUpdateDate;
    return TenvpnSettingsRow(
      icon: Symbols.sync,
      title: l.tenvpnUpdateSubscription,
      subtitle: updated == null
          ? null
          : l.tenvpnUpdatedAt(updated.getLastUpdateTimeDesc(context)),
      trailing: updating
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      onTap: profile == null || updating
          ? null
          : () => globalState.safeRun(
              () => ref
                  .read(profilesActionProvider.notifier)
                  .updateProfile(profile, showLoading: true),
            ),
    );
  }
}

class _ThemeRow extends ConsumerWidget {
  const _ThemeRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.appLocalizations;
    final mode = ref.watch(themeSettingProvider.select((s) => s.themeMode));
    return Padding(
      padding: const EdgeInsets.all(14),
      child: SizedBox(
        width: double.infinity,
        child: SegmentedButton<ThemeMode>(
          key: const ValueKey('tenvpn-theme'),
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: ThemeMode.dark,
              label: Text(l.tenvpnThemeDark),
            ),
            ButtonSegment(
              value: ThemeMode.light,
              label: Text(l.tenvpnThemeLight),
            ),
            ButtonSegment(
              value: ThemeMode.system,
              label: Text(l.tenvpnThemeSystem),
            ),
          ],
          selected: {mode},
          onSelectionChanged: (value) => ref
              .read(themeSettingProvider.notifier)
              .update((s) => s.copyWith(themeMode: value.first)),
        ),
      ),
    );
  }
}

class _LanguageRow extends ConsumerWidget {
  const _LanguageRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.appLocalizations;
    final p = context.palette;
    final locale = ref.watch(appSettingProvider.select((s) => s.locale));
    final english = locale?.startsWith('en') == true;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Row(
        children: [
          Icon(Symbols.language, color: p.cocoaText),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l.tenvpnLanguage,
              style: TextStyle(fontSize: 15.5, color: p.text),
            ),
          ),
          SegmentedButton<bool>(
            key: const ValueKey('tenvpn-language'),
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('Русский')),
              ButtonSegment(value: true, label: Text('English')),
            ],
            selected: {english},
            onSelectionChanged: (value) => ref
                .read(appSettingProvider.notifier)
                .update((s) => s.copyWith(locale: value.first ? 'en' : 'ru')),
          ),
        ],
      ),
    );
  }
}

class _SettingsHeader extends ConsumerWidget {
  const _SettingsHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final phase = ref.watch(tenvpnPhaseProvider);
    return Row(
      children: [
        FerMascot(pose: ferPoseFor(phase), size: 112),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const TenvpnLogo(size: 22),
              const SizedBox(height: 4),
              Text(
                context.appLocalizations.tenvpnVersion(
                  globalState.packageInfo.version,
                ),
                style: TextStyle(fontSize: 13, color: p.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Choice<T> extends StatelessWidget {
  final IconData icon;
  final String title;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  const _Choice({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: p.cocoaText),
              const SizedBox(width: 12),
              Text(title, style: TextStyle(fontSize: 15.5, color: p.text)),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<T>(
              showSelectedIcon: false,
              segments: [
                for (final (option, label) in options)
                  ButtonSegment(value: option, label: Text(label)),
              ],
              selected: {value},
              onSelectionChanged: (value) => onChanged(value.first),
            ),
          ),
        ],
      ),
    );
  }
}

class _ListStyleRow extends ConsumerWidget {
  const _ListStyleRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.appLocalizations;
    return _Choice<ServerListStyle>(
      key: const ValueKey('tenvpn-list-style'),
      icon: Symbols.view_agenda,
      title: l.tenvpnListStyle,
      value: ref.watch(appSettingProvider.select((s) => s.serverListStyle)),
      options: [
        (ServerListStyle.compact, l.tenvpnListCompact),
        (ServerListStyle.detailed, l.tenvpnListDetailed),
      ],
      onChanged: (value) => ref
          .read(appSettingProvider.notifier)
          .update((s) => s.copyWith(serverListStyle: value)),
    );
  }
}

class _SortRow extends ConsumerWidget {
  const _SortRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.appLocalizations;
    return _Choice<ServerSort>(
      key: const ValueKey('tenvpn-sort'),
      icon: Symbols.sort,
      title: l.tenvpnSort,
      value: ref.watch(appSettingProvider.select((s) => s.serverSort)),
      options: [
        (ServerSort.subscription, l.tenvpnSortSubscription),
        (ServerSort.ping, l.tenvpnSortPing),
      ],
      onChanged: (value) => ref
          .read(appSettingProvider.notifier)
          .update((s) => s.copyWith(serverSort: value)),
    );
  }
}
