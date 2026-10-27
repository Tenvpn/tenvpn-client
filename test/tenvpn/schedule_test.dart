import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/tenvpn/schedule.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // 2026-10-26 is a Monday.
  DateTime at(int day, int hour, [int minute = 0]) =>
      DateTime(2026, 10, day, hour, minute);
  const evening = TenvpnScheduleSlot(start: 18 * 60, end: 21 * 60);
  const night = TenvpnScheduleSlot(start: 23 * 60, end: 7 * 60);

  test('an evening window is on inside and off outside', () {
    expect(scheduleActiveAt([evening], at(26, 17, 59)), isFalse);
    expect(scheduleActiveAt([evening], at(26, 18)), isTrue);
    expect(scheduleActiveAt([evening], at(26, 20, 59)), isTrue);
    expect(scheduleActiveAt([evening], at(26, 21)), isFalse);
    expect(nextScheduleChange([evening], at(26, 12)), at(26, 18));
    expect(nextScheduleChange([evening], at(26, 19)), at(26, 21));
    expect(nextScheduleChange([evening], at(26, 22)), at(27, 18));
  });

  test('a window past midnight belongs to the day it starts', () {
    const weekdays = TenvpnScheduleSlot(
      start: 23 * 60,
      end: 7 * 60,
      days: [1, 2, 3, 4, 5],
    );
    expect(scheduleActiveAt([night], at(27, 3)), isTrue);
    expect(nextScheduleChange([night], at(27, 3)), at(27, 7));
    // Friday 23:00 → Saturday 07:00 runs, Saturday night does not.
    expect(scheduleActiveAt([weekdays], at(31, 3)), isTrue);
    expect(scheduleActiveAt([weekdays], at(31, 23, 30)), isFalse);
    expect(
      nextScheduleChange([weekdays], at(31, 8)),
      DateTime(2026, 11, 2, 23),
    );
  });

  test('touching windows make one change, not two', () {
    const day = TenvpnScheduleSlot(start: 7 * 60, end: 23 * 60);
    expect(nextScheduleChange([day, night], at(26, 12)), isNull);
    const morning = TenvpnScheduleSlot(start: 9 * 60, end: 12 * 60);
    const noon = TenvpnScheduleSlot(start: 12 * 60, end: 14 * 60);
    expect(nextScheduleChange([morning, noon], at(26, 10)), at(26, 14));
  });

  test('no slots or no matching days never turn on', () {
    expect(scheduleActiveAt([], at(26, 12)), isFalse);
    expect(nextScheduleChange([], at(26, 12)), isNull);
    const never = TenvpnScheduleSlot(start: 60, end: 120, days: []);
    expect(nextScheduleChange([never], at(26, 12)), isNull);
  });

  test('times read as HH:MM', () {
    expect(formatScheduleMinutes(0), '00:00');
    expect(formatScheduleMinutes(18 * 60 + 5), '18:05');
  });
}
