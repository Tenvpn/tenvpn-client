/// The Google Play build is a plain VPN connector: no proxy-only mode, no
/// Wi-Fi rules and no QR scanner, matching its trimmed manifest.
const isPlayBuild = String.fromEnvironment('TENVPN_STORE') == 'play';
