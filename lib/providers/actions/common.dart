part of '../action.dart';

@Riverpod(keepAlive: true)
class CommonAction extends _$CommonAction {
  CoreController get _core => ref.read(coreHandlerProvider);
  bool _isUpdatingTraffic = false;

  @override
  void build() {}

  void toggleRunning() {
    final running = !ref.read(isStartProvider);
    unawaited(
      globalState.safeRun(
        () => ref
            .read(setupActionProvider.notifier)
            .setRunning(
              running,
              initialize: running && !ref.read(initProvider),
            ),
      ),
    );
  }

  /// Stop and start again: drops stuck connections, re-reads the subscription
  /// if due and lets «Авто» pick afresh.
  Future<void> reconnect() async {
    if (!ref.read(isStartProvider)) return;
    final setup = ref.read(setupActionProvider.notifier);
    await globalState.safeRun(() async {
      await setup.setRunning(false);
      await setup.setRunning(true);
    });
  }

  void updateSpeedStatistics() {
    ref
        .read(vpnSettingProvider.notifier)
        .update(
          (state) => state.copyWith(
            networkSpeedNotification: !state.networkSpeedNotification,
          ),
        );
  }

  void updateMode() {
    ref.read(patchClashConfigProvider.notifier).update((state) {
      final index = Mode.values.indexWhere((item) => item == state.mode);
      if (index == -1) return state;
      final nextIndex = index + 1 > Mode.values.length - 1 ? 0 : index + 1;
      return state.copyWith(mode: Mode.values[nextIndex]);
    });
  }

  Future<void> updateTraffic() async {
    if (_isUpdatingTraffic) {
      return;
    }
    _isUpdatingTraffic = true;
    try {
      final onlyStatisticsProxy = ref.read(
        appSettingProvider.select((state) => state.onlyStatisticsProxy),
      );
      final [traffic, totalTraffic] = await Future.wait([
        _readTraffic(() => _core.getTraffic(onlyStatisticsProxy)),
        _readTraffic(() => _core.getTotalTraffic(onlyStatisticsProxy)),
      ]);
      if (traffic != null) {
        ref.read(trafficsProvider.notifier).addTraffic(traffic);
      }
      if (totalTraffic != null) {
        ref.read(totalTrafficProvider.notifier).value = totalTraffic;
      }
    } finally {
      _isUpdatingTraffic = false;
    }
  }

  Future<Traffic?> _readTraffic(Future<Traffic> Function() request) async {
    try {
      return await request();
    } catch (error) {
      commonPrint.log(
        'updateTraffic error: $error',
        logLevel: coreFailureLogLevel(error),
      );
      return null;
    }
  }

  Future<bool> autoCheckUpdate() async {
    if (!ref.read(appSettingProvider).autoCheckUpdate) return false;
    try {
      final res = await request.checkForUpdate();
      await checkUpdateResultHandle(data: res);
      return res != null;
    } catch (error, stackTrace) {
      commonPrint.log(
        'autoCheckUpdate failed: $error\n$stackTrace',
        logLevel: LogLevel.warning,
      );
      return false;
    }
  }

  TextSpan _releaseSpan(BuildContext context, String tagName, String? body) {
    final textTheme = context.textTheme;
    final version = parseReleaseChangelog(body);
    return TextSpan(
      text: '$tagName \n',
      style: textTheme.headlineSmall,
      children: version == null
          ? [
              TextSpan(text: '\n', style: textTheme.bodyMedium),
              for (final submit in parseReleaseBody(body))
                TextSpan(text: '- $submit \n', style: textTheme.bodyMedium),
            ]
          : _changelogSpans(context, version),
    );
  }

  List<TextSpan> _changelogSpans(
    BuildContext context,
    ChangelogVersion version,
  ) {
    final textTheme = context.textTheme;
    return [
      for (final group in version.visibleGroups) ...[
        TextSpan(
          text:
              '\n${changelogGroupTitle(currentAppLocalizations, group.type)}\n',
          style: textTheme.labelLarge?.copyWith(
            color: group.type == ChangelogType.breaking
                ? context.colorScheme.error
                : context.colorScheme.primary,
          ),
        ),
        for (final entry in group.entries)
          TextSpan(text: '• ${entry.text}\n', style: textTheme.bodyMedium),
      ],
    ];
  }

  /// Settings → «Проверить обновления»: unlike the start-up check, says so
  /// when there is nothing newer.
  Future<void> checkUpdateByUser() async {
    await globalState.safeRun(() async {
      final data = await request.checkForUpdate();
      if (data == null) {
        await dialogs.showMessage(
          title: currentAppLocalizations.tenvpnCheckUpdate,
          message: TextSpan(text: currentAppLocalizations.tenvpnUpToDate),
          cancelable: false,
        );
        return;
      }
      await checkUpdateResultHandle(data: data, isUser: true);
    });
  }

  Future<void> _offerWindowsUpdate(
    UpdateProgressPort port,
    UpdateRelease release,
    String? body,
  ) async {
    final l = currentAppLocalizations;
    final context = globalState.navigatorKey.currentContext!;
    final accepted = await dialogs.showMessage(
      title: l.tenvpnUpdateTitle(release.version),
      message: TextSpan(
        children: [
          TextSpan(text: '${l.tenvpnUpdateText}\n\n'),
          _releaseSpan(context, release.tag, body),
        ],
      ),
      confirmText: l.tenvpnUpdateNow,
      cancelText: l.tenvpnUpdateLater,
    );
    if (accepted != true) return;
    final reconnect = ref.read(isStartProvider);
    Future<void> task(void Function(double) onProgress) => tenvpnWindowsUpdater
        .install(release, reconnect: reconnect, onProgress: onProgress);
    final error = await port.run(task);
    if (error == null) {
      await ref.read(systemActionProvider.notifier).handleExit();
      return;
    }
    commonPrint.log('update failed: $error', logLevel: LogLevel.warning);
    final reason = switch (error) {
      UpdateException(failure: UpdateFailure.noInstaller) =>
        l.tenvpnUpdateNoInstaller,
      UpdateException(failure: UpdateFailure.broken) => l.tenvpnUpdateBroken,
      UpdateException(failure: UpdateFailure.declined) =>
        l.tenvpnUpdateDeclined,
      _ => compactError(error),
    };
    final download = await dialogs.showMessage(
      title: appName,
      message: TextSpan(text: l.tenvpnUpdateFailed(reason)),
      confirmText: l.goDownload,
    );
    if (download == true) {
      unawaited(
        launchUrl(Uri.parse('https://github.com/$repository/releases/latest')),
      );
    }
  }

  Future<void> checkUpdateResultHandle({
    Map<String, dynamic>? data,
    bool isUser = false,
  }) async {
    if (data != null) {
      final port = updateProgressPort;
      final release = port != null && system.isWindows && !appPath.isPortable
          ? UpdateRelease.fromJson(data)
          : null;
      if (port != null && release != null) {
        await _offerWindowsUpdate(port, release, data['body'] as String?);
        return;
      }
      final context = globalState.navigatorKey.currentContext!;
      final res = await dialogs.showMessage(
        title: currentAppLocalizations.discoverNewVersion,
        message: _releaseSpan(
          context,
          data['tag_name'] as String,
          data['body'] as String?,
        ),
        confirmText: currentAppLocalizations.goDownload,
        cancelText: isUser ? null : currentAppLocalizations.noLongerRemind,
      );
      if (res == true) {
        unawaited(
          launchUrl(
            Uri.parse('https://github.com/$repository/releases/latest'),
          ),
        );
      } else if (!isUser && res == false) {
        ref
            .read(appSettingProvider.notifier)
            .update((state) => state.copyWith(autoCheckUpdate: false));
      }
    } else if (isUser) {
      unawaited(
        dialogs.showMessage(
          title: currentAppLocalizations.checkUpdate,
          message: TextSpan(text: currentAppLocalizations.checkUpdateError),
        ),
      );
    }
  }
}
