import 'dart:async';

import 'package:fl_clash/tenvpn/network_recheck.dart';
import 'package:flutter_test/flutter_test.dart';

class _Clock {
  DateTime now = DateTime(2026, 11, 8, 12);
  final List<_FakeTimer> timers = [];

  Timer start(Duration delay, void Function() callback) {
    final timer = _FakeTimer(now.add(delay), callback);
    timers.add(timer);
    return timer;
  }

  Future<void> advance(Duration by) async {
    final end = now.add(by);
    while (true) {
      final due =
          timers.where((t) => t.isActive && !t.due.isAfter(end)).toList()
            ..sort((a, b) => a.due.compareTo(b.due));
      if (due.isEmpty) break;
      final next = due.first;
      now = next.due;
      next.fire();
      await pumpEventQueue();
    }
    now = end;
  }
}

class _FakeTimer implements Timer {
  final DateTime due;
  final void Function() callback;
  bool _active = true;

  _FakeTimer(this.due, this.callback);

  void fire() {
    _active = false;
    callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;
}

void main() {
  late _Clock clock;
  late List<DateTime> runs;
  late bool active;
  Completer<void>? hold;

  NetworkRecheck recheck() => NetworkRecheck(
    isActive: () => active,
    run: () async {
      runs.add(clock.now);
      await hold?.future;
    },
    now: () => clock.now,
    timer: clock.start,
  );

  setUp(() {
    clock = _Clock();
    runs = [];
    active = true;
    hold = null;
  });

  test('re-measures once the network has settled', () async {
    final subject = recheck()..networkChanged();
    await clock.advance(const Duration(seconds: 3));
    expect(runs, isEmpty);
    await clock.advance(const Duration(seconds: 1));
    expect(runs, hasLength(1));
    expect(subject.scheduled, isFalse);
  });

  test('a burst of changes settles into one run', () async {
    final subject = recheck();
    for (var i = 0; i < 5; i++) {
      subject.networkChanged();
      await clock.advance(const Duration(seconds: 1));
    }
    expect(runs, isEmpty);
    await clock.advance(networkRecheckSettle);
    expect(runs, hasLength(1));
  });

  test('never runs twice within ten seconds', () async {
    final subject = recheck()..networkChanged();
    await clock.advance(networkRecheckSettle);
    final first = runs.single;

    subject.networkChanged();
    await clock.advance(const Duration(seconds: 5));
    expect(runs, hasLength(1), reason: 'the gap outlasts the settle delay');
    await clock.advance(const Duration(seconds: 5));
    expect(runs, hasLength(2));
    expect(runs.last.difference(first), networkRecheckGap);

    await clock.advance(const Duration(seconds: 20));
    final changedAt = clock.now;
    subject.networkChanged();
    await clock.advance(const Duration(seconds: 30));
    expect(runs, hasLength(3));
    expect(
      runs.last.difference(changedAt),
      networkRecheckSettle,
      reason: 'past the gap a change only waits to settle',
    );
  });

  test('does nothing while the VPN is off', () async {
    active = false;
    recheck().networkChanged();
    await clock.advance(const Duration(minutes: 1));
    expect(runs, isEmpty);
  });

  test('a change during a run repeats it after the run', () async {
    hold = Completer();
    final subject = recheck()..networkChanged();
    await clock.advance(networkRecheckSettle);
    expect(runs, hasLength(1));

    subject.networkChanged();
    expect(subject.scheduled, isFalse, reason: 'not stacked on the live run');
    hold!.complete();
    await pumpEventQueue();
    expect(subject.scheduled, isTrue);
    await clock.advance(networkRecheckGap);
    expect(runs, hasLength(2));
  });

  test('cancel drops a pending run', () async {
    final subject = recheck()..networkChanged();
    subject.cancel();
    await clock.advance(const Duration(minutes: 1));
    expect(runs, isEmpty);
  });
}
