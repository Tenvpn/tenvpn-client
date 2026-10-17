import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// A build may point updates at a mirror with the same JSON shape as GitHub's
/// `releases/latest`, for networks where GitHub is slow or cut off.
const tenvpnReleasesUrl = String.fromEnvironment('TENVPN_RELEASES_URL');

const windowsInstallerSuffix = '-windows-amd64-setup.exe';
const checksumsAssetName = 'SHA256SUMS.txt';

class ReleaseAsset {
  final String name;
  final Uri url;

  const ReleaseAsset(this.name, this.url);
}

class UpdateRelease {
  final String tag;
  final ReleaseAsset? installer;
  final ReleaseAsset? checksums;

  const UpdateRelease({required this.tag, this.installer, this.checksums});

  String get version => tag.startsWith('v') ? tag.substring(1) : tag;

  static UpdateRelease? fromJson(
    Map<String, dynamic> json, {
    String installerSuffix = windowsInstallerSuffix,
  }) {
    final tag = json['tag_name'];
    if (tag is! String || tag.isEmpty) return null;
    ReleaseAsset? installer;
    ReleaseAsset? checksums;
    for (final asset in json['assets'] as List? ?? const []) {
      if (asset is! Map) continue;
      final name = asset['name'];
      final url = Uri.tryParse('${asset['browser_download_url']}');
      if (name is! String || url == null || url.scheme != 'https') continue;
      if (name.endsWith(installerSuffix)) installer = ReleaseAsset(name, url);
      if (name == checksumsAssetName) checksums = ReleaseAsset(name, url);
    }
    return UpdateRelease(tag: tag, installer: installer, checksums: checksums);
  }
}

/// `sha256sum` output: `<hex>  <name>` or `<hex> *<name>` in binary mode.
String? checksumFor(String sums, String fileName) {
  for (final line in sums.split('\n')) {
    final match = RegExp(
      r'^([0-9a-fA-F]{64})\s+\*?(.+?)\s*$',
    ).firstMatch(line.trim());
    if (match != null && match.group(2) == fileName) {
      return match.group(1)!.toLowerCase();
    }
  }
  return null;
}

enum UpdateFailure { noInstaller, broken, declined }

class UpdateException implements Exception {
  final UpdateFailure failure;

  const UpdateException(this.failure);

  @override
  String toString() => 'UpdateException(${failure.name})';
}

typedef UpdateTextFetcher = Future<String> Function(Uri url);
typedef UpdateDownloader =
    Future<void> Function(
      Uri url,
      String savePath,
      void Function(int received, int total) onProgress,
    );

/// Runs the installer and completes with its exit code. Setup asks for UAC
/// itself; started through `runas`, its "original user" would be elevated and
/// the relaunched app would run as administrator.
typedef InstallerRunner =
    Future<int> Function(String executable, List<String> arguments);

/// Downloads the Inno Setup installer of a release, checks it against the
/// release's SHA256SUMS.txt and starts it silently; the installer relaunches
/// the app itself.
class WindowsUpdater {
  final UpdateTextFetcher fetchText;
  final UpdateDownloader download;
  final InstallerRunner runInstaller;
  final Future<String> Function() workDir;

  const WindowsUpdater({
    required this.fetchText,
    required this.download,
    required this.runInstaller,
    required this.workDir,
  });

  static List<String> installerArguments({required bool reconnect}) => [
    '/SILENT',
    '/SUPPRESSMSGBOXES',
    '/NORESTART',
    '/SP-',
    if (reconnect) '/relaunch=--connect',
  ];

  Future<void> install(
    UpdateRelease release, {
    required bool reconnect,
    void Function(double progress)? onProgress,
  }) async {
    final installer = release.installer;
    final checksums = release.checksums;
    if (installer == null) {
      throw const UpdateException(UpdateFailure.noInstaller);
    }
    if (checksums == null) throw const UpdateException(UpdateFailure.broken);
    final expected = checksumFor(
      await fetchText(checksums.url),
      installer.name,
    );
    if (expected == null) throw const UpdateException(UpdateFailure.broken);
    final dir = Directory(p.join(await workDir(), 'update'));
    if (await dir.exists()) await dir.delete(recursive: true);
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, installer.name));
    await download(installer.url, file.path, (received, total) {
      if (total > 0) onProgress?.call(received / total);
    });
    final actual = (await sha256.bind(file.openRead()).first).toString();
    if (actual != expected) {
      await file.delete();
      throw const UpdateException(UpdateFailure.broken);
    }
    // A successful install kills this process before setup exits, so only
    // a refused UAC prompt or a failed setup ever returns here.
    final exitCode = await runInstaller(
      file.path,
      installerArguments(reconnect: reconnect),
    );
    if (exitCode != 0) throw const UpdateException(UpdateFailure.declined);
  }
}
