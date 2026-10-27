import 'package:fl_clash/models/models.dart';

const minutesPerDay = 24 * 60;

(DateTime, DateTime)? scheduleWindow(TenvpnScheduleSlot slot, DateTime day) {
  if (!slot.days.contains(day.weekday)) return null;
  final start = DateTime(day.year, day.month, day.day, 0, slot.start);
  final endDay = slot.end > slot.start ? 0 : 1;
  final end = DateTime(day.year, day.month, day.day + endDay, 0, slot.end);
  return (start, end);
}

Iterable<(DateTime, DateTime)> _windowsAround(
  List<TenvpnScheduleSlot> slots,
  DateTime at,
) sync* {
  for (var offset = -1; offset <= 7; offset++) {
    final day = DateTime(at.year, at.month, at.day + offset);
    for (final slot in slots) {
      final window = scheduleWindow(slot, day);
      if (window != null) yield window;
    }
  }
}

bool scheduleActiveAt(List<TenvpnScheduleSlot> slots, DateTime at) =>
    _windowsAround(
      slots,
      at,
    ).any((w) => !at.isBefore(w.$1) && at.isBefore(w.$2));

/// The first moment after [at] when the VPN should flip on or off; null for
/// an empty schedule. Touching windows count as one.
DateTime? nextScheduleChange(List<TenvpnScheduleSlot> slots, DateTime at) {
  final now = scheduleActiveAt(slots, at);
  final edges = {
    for (final (start, end) in _windowsAround(slots, at)) ...[start, end],
  }.where((t) => t.isAfter(at)).toList()..sort();
  for (final edge in edges) {
    if (scheduleActiveAt(slots, edge) != now) return edge;
  }
  return null;
}

String formatScheduleMinutes(int minutes) {
  final m = minutes % minutesPerDay;
  return '${(m ~/ 60).toString().padLeft(2, '0')}:'
      '${(m % 60).toString().padLeft(2, '0')}';
}
