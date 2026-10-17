import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:material_ui/material_ui.dart';

/// Runs [task] while showing its progress; pops with the error, or with null
/// once the installer has been started.
class TenvpnUpdateDialog extends StatefulWidget {
  final UpdateTask task;

  const TenvpnUpdateDialog({super.key, required this.task});

  @override
  State<TenvpnUpdateDialog> createState() => _TenvpnUpdateDialogState();
}

class _TenvpnUpdateDialogState extends State<TenvpnUpdateDialog> {
  final _progress = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    Object? error;
    try {
      await widget.task((value) => _progress.value = value);
    } catch (e) {
      error = e;
    }
    if (mounted) Navigator.of(context).pop(error);
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    return PopScope(
      canPop: false,
      child: CommonDialog(
        title: appName,
        child: ValueListenableBuilder<double>(
          valueListenable: _progress,
          builder: (context, value, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l.tenvpnUpdateDownloading((value * 100).round())),
              const SizedBox(height: 16),
              LinearProgressIndicator(value: value == 0 ? null : value),
            ],
          ),
        ),
      ),
    );
  }
}

class TenvpnUpdateProgress implements UpdateProgressPort {
  const TenvpnUpdateProgress();

  @override
  Future<Object?> run(UpdateTask task) => dialogs.showCommonDialog<Object?>(
    dismissible: false,
    child: TenvpnUpdateDialog(task: task),
  );
}
