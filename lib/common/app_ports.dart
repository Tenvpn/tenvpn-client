import 'package:fl_clash/common/provider_reader.dart';
import 'package:fl_clash/models/models.dart';

abstract interface class WindowPort {
  Future<WindowProps?> captureNormalGeometry(WindowProps current);

  Future<void> show();

  Future<void> hide();

  Future<void> toggle();

  Future<void> close();

  void forceExit();
}

abstract interface class TrayPort {
  Future<void> shutdown();

  Future<void> update({
    required TrayState trayState,
    required Traffic traffic,
    required ProviderReader read,
  });
}

abstract interface class NavigationPort {
  List<NavigationItem> getItems({
    bool openLogs,
    bool hasProxies,
    bool hasNetworking,
  });
}

typedef UpdateTask = Future<void> Function(void Function(double) onProgress);

abstract interface class UpdateProgressPort {
  /// Runs [task] under a progress dialog; completes with its error, or null.
  Future<Object?> run(UpdateTask task);
}

WindowPort? windowPort;
UpdateProgressPort? updateProgressPort;
TrayPort? trayPort;
NavigationPort? navigationPort;
