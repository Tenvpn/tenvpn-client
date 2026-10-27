import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/plugins/app.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/tenvpn/tenvpn.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'main_view.dart' show tenvpnContentWidth;
import 'settings_view.dart';
import 'theme.dart';

const _newSlot = TenvpnScheduleSlot(start: 18 * 60, end: 21 * 60);

/// Hands the windows to Android, which keeps them across reboots; any other
/// mode clears the alarm.
Future<void> syncTenvpnSchedule(AppSettingProps settings) async =>
    app?.setVpnSchedule(
      settings.tenvpnBatteryMode == TenvpnBatteryMode.schedule
          ? settings.tenvpnSchedule
          : null,
    );

String tenvpnBatteryModeLabel(AppLocalizations l, TenvpnBatteryMode mode) =>
    switch (mode) {
      TenvpnBatteryMode.always => l.tenvpnBatteryAlways,
      TenvpnBatteryMode.saver => l.tenvpnBatterySaver,
      TenvpnBatteryMode.schedule => l.tenvpnBatterySchedule,
    };

class TenvpnBatteryView extends ConsumerWidget {
  final Future<bool?> Function()? readBackground;

  const TenvpnBatteryView({super.key, this.readBackground});

  Future<void> _setMode(WidgetRef ref, TenvpnBatteryMode mode) async {
    final before = ref.read(appSettingProvider).tenvpnBatteryMode;
    if (before == mode) return;
    ref
        .read(appSettingProvider.notifier)
        .update((s) => s.copyWith(tenvpnBatteryMode: mode));
    await syncTenvpnSchedule(ref.read(appSettingProvider));
    final checksChanged =
        (before == TenvpnBatteryMode.saver) !=
        (mode == TenvpnBatteryMode.saver);
    final profile = ref.read(currentProfileProvider);
    if (!checksChanged || profile == null) return;
    await globalState.safeRun(
      () =>
          ref.read(profilesActionProvider.notifier).regenerateProfile(profile),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.appLocalizations;
    final p = context.palette;
    final mode = ref.watch(
      appSettingProvider.select((s) => s.tenvpnBatteryMode),
    );
    return Scaffold(
      appBar: AppBar(title: Text(l.tenvpnBattery)),
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
              TenvpnSettingsGroup(
                title: l.tenvpnBattery,
                children: [
                  for (final option in TenvpnBatteryMode.values)
                    TenvpnSettingsRow(
                      key: ValueKey('tenvpn-battery-${option.name}'),
                      icon: switch (option) {
                        TenvpnBatteryMode.always => Symbols.bolt,
                        TenvpnBatteryMode.saver => Symbols.battery_saver,
                        TenvpnBatteryMode.schedule => Symbols.schedule,
                      },
                      title: tenvpnBatteryModeLabel(l, option),
                      subtitle: switch (option) {
                        TenvpnBatteryMode.always => l.tenvpnBatteryAlwaysDesc,
                        TenvpnBatteryMode.saver => l.tenvpnBatterySaverDesc,
                        TenvpnBatteryMode.schedule =>
                          l.tenvpnBatteryScheduleDesc,
                      },
                      trailing: Icon(
                        option == mode
                            ? Symbols.radio_button_checked
                            : Symbols.radio_button_unchecked,
                        color: option == mode ? p.accentText : p.muted,
                      ),
                      onTap: () => unawaited(_setMode(ref, option)),
                    ),
                  _BackgroundRow(read: readBackground),
                ],
              ),
              if (mode == TenvpnBatteryMode.schedule) const _ScheduleGroup(),
            ],
          ),
        ),
      ),
    );
  }
}

class _BackgroundRow extends StatefulWidget {
  final Future<bool?> Function()? read;

  const _BackgroundRow({this.read});

  @override
  State<_BackgroundRow> createState() => _BackgroundRowState();
}

class _BackgroundRowState extends State<_BackgroundRow> {
  late final AppLifecycleListener _lifecycle;
  bool? _allowed;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refresh);
    _refresh();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _refresh() {
    final read =
        widget.read ?? () async => app?.isBatteryOptimizationDisabled();
    unawaited(
      read().then((allowed) {
        if (mounted) setState(() => _allowed = allowed);
      }, onError: (_) {}),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final p = context.palette;
    final allowed = _allowed ?? false;
    return TenvpnSettingsRow(
      key: const ValueKey('tenvpn-battery-background'),
      icon: Symbols.nights_stay,
      title: l.tenvpnBatteryBackground,
      subtitle: l.tenvpnBatteryBackgroundDesc,
      onTap: allowed
          ? null
          : () => unawaited(app?.openBatteryOptimizationSettings()),
      trailing: Text(
        allowed
            ? l.tenvpnBatteryBackgroundAllowed
            : l.tenvpnBatteryBackgroundAllow,
        key: const ValueKey('tenvpn-battery-background-state'),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: allowed ? p.muted : p.accentText,
        ),
      ),
    );
  }
}

class _ScheduleGroup extends ConsumerWidget {
  const _ScheduleGroup();

  Future<void> _save(WidgetRef ref, List<TenvpnScheduleSlot> slots) async {
    ref
        .read(appSettingProvider.notifier)
        .update((s) => s.copyWith(tenvpnSchedule: slots));
    await syncTenvpnSchedule(ref.read(appSettingProvider));
  }

  Future<int?> _pickTime(BuildContext context, int minutes) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    return picked == null ? null : picked.hour * 60 + picked.minute;
  }

  String _nextChange(BuildContext context, List<TenvpnScheduleSlot> slots) {
    final l = context.appLocalizations;
    final now = DateTime.now();
    final next = nextScheduleChange(slots, now);
    if (next == null) return l.tenvpnScheduleEmpty;
    final sameDay =
        next.year == now.year && next.month == now.month && next.day == now.day;
    final clock = formatScheduleMinutes(next.hour * 60 + next.minute);
    final locale = Localizations.localeOf(context).toString();
    final time = sameDay
        ? clock
        : '${DateFormat.E(locale).format(next)} $clock';
    return scheduleActiveAt(slots, now)
        ? l.tenvpnScheduleNextOff(time)
        : l.tenvpnScheduleNextOn(time);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.appLocalizations;
    final p = context.palette;
    final slots = ref.watch(appSettingProvider.select((s) => s.tenvpnSchedule));
    final locale = Localizations.localeOf(context).toString();
    // 2026-10-26 is a Monday: ISO weekday d falls on the 25th + d.
    String dayName(int d) =>
        DateFormat.E(locale).format(DateTime(2026, 10, 25 + d));
    return TenvpnSettingsGroup(
      title: l.tenvpnBatterySchedule,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            _nextChange(context, slots),
            key: const ValueKey('tenvpn-schedule-next'),
            style: TextStyle(fontSize: 14, color: p.text),
          ),
        ),
        for (final (index, slot) in slots.indexed)
          Padding(
            key: ValueKey('tenvpn-schedule-slot-$index'),
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    TextButton(
                      onPressed: () async {
                        final start = await _pickTime(context, slot.start);
                        if (start == null) return;
                        await _save(
                          ref,
                          [...slots]..[index] = slot.copyWith(start: start),
                        );
                      },
                      child: Text(formatScheduleMinutes(slot.start)),
                    ),
                    Text('—', style: TextStyle(color: p.muted)),
                    TextButton(
                      onPressed: () async {
                        final end = await _pickTime(context, slot.end);
                        if (end == null) return;
                        await _save(
                          ref,
                          [...slots]..[index] = slot.copyWith(end: end),
                        );
                      },
                      child: Text(formatScheduleMinutes(slot.end)),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: l.tenvpnScheduleRemove,
                      icon: Icon(Symbols.delete, color: p.muted),
                      onPressed: () =>
                          unawaited(_save(ref, [...slots]..removeAt(index))),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var d = 1; d <= 7; d++)
                      FilterChip(
                        label: Text(dayName(d)),
                        selected: slot.days.contains(d),
                        showCheckmark: false,
                        onSelected: (on) => unawaited(
                          _save(
                            ref,
                            [...slots]
                              ..[index] = slot.copyWith(
                                days: on
                                    ? ([...slot.days, d]..sort())
                                    : [...slot.days.where((x) => x != d)],
                              ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        TenvpnSettingsRow(
          key: const ValueKey('tenvpn-schedule-add'),
          icon: Symbols.add,
          title: l.tenvpnScheduleAdd,
          onTap: () => unawaited(_save(ref, [...slots, _newSlot])),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
          child: Text(
            l.tenvpnScheduleLockdown,
            style: TextStyle(fontSize: 13, color: p.muted),
          ),
        ),
      ],
    );
  }
}
