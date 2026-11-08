import 'dart:async';

typedef RecheckTimer = Timer Function(Duration delay, void Function() callback);

const networkRecheckSettle = Duration(seconds: 4);
const networkRecheckGap = Duration(seconds: 10);

/// The core re-checks its groups only on their interval (120 s for the regular
/// tier), so after Wi-Fi ↔ mobile the list kept the old network's timeouts.
class NetworkRecheck {
  final bool Function() isActive;
  final Future<void> Function() run;
  final Duration settle;
  final Duration minGap;
  final DateTime Function() _now;
  final RecheckTimer _timer;
  Timer? _pending;
  DateTime? _lastRun;
  bool _running = false;
  bool _again = false;

  NetworkRecheck({
    required this.isActive,
    required this.run,
    this.settle = networkRecheckSettle,
    this.minGap = networkRecheckGap,
    DateTime Function()? now,
    RecheckTimer? timer,
  }) : _now = now ?? DateTime.now,
       _timer = timer ?? Timer.new;

  bool get scheduled => _pending != null;

  void networkChanged() {
    if (_running) {
      _again = true;
      return;
    }
    _pending?.cancel();
    final last = _lastRun;
    final left = last == null
        ? Duration.zero
        : minGap - _now().difference(last);
    _pending = _timer(left > settle ? left : settle, () => unawaited(_fire()));
  }

  Future<void> _fire() async {
    _pending = null;
    if (!isActive()) return;
    _running = true;
    _lastRun = _now();
    try {
      await run();
    } finally {
      _running = false;
    }
    if (_again) {
      _again = false;
      networkChanged();
    }
  }

  void cancel() {
    _pending?.cancel();
    _pending = null;
    _again = false;
  }
}
