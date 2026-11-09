import 'package:flutter/foundation.dart';

/// The Google Play build is a plain VPN connector: no proxy-only mode, no
/// Wi-Fi rules and no QR scanner, matching its trimmed manifest.
const isPlayBuild = String.fromEnvironment('TENVPN_STORE') == 'play';

/// Google Play delivers its own updates and forbids an app updating itself
/// from elsewhere, so the Play build never asks GitHub for a newer release
/// and offers no «Скачать». The site APK and Windows keep both.
bool get selfUpdateEnabled => debugSelfUpdateEnabled ?? !isPlayBuild;

/// Lets a test run either build's update paths.
@visibleForTesting
bool? debugSelfUpdateEnabled;
