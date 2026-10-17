const autostartArg = '--autostart';
const connectArg = '--connect';

/// Flags the app was started with: by Windows at logon (stay in the tray) or
/// by the installer after an in-app update (reconnect if it was connected).
class LaunchArgs {
  final bool autostart;
  final bool connect;

  const LaunchArgs({this.autostart = false, this.connect = false});

  factory LaunchArgs.parse(List<String> args) => LaunchArgs(
    autostart: args.contains(autostartArg),
    connect: args.contains(connectArg),
  );
}

LaunchArgs launchArgs = const LaunchArgs();
