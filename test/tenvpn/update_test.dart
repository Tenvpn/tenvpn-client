import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fl_clash/tenvpn/update.dart';
import 'package:flutter_test/flutter_test.dart';

const _installer = 'TENVPN-0.2.0-windows-amd64-setup.exe';
final _bytes = List<int>.generate(4096, (i) => i % 251);
final _hash = sha256.convert(_bytes).toString();

Map<String, dynamic> _release({List<Map<String, String>>? assets}) => {
  'tag_name': 'v0.2.0',
  'assets':
      assets ??
      [
        {
          'name': 'TENVPN-0.2.0-android-arm64-v8a.apk',
          'browser_download_url': 'https://example.com/a.apk',
        },
        {
          'name': _installer,
          'browser_download_url': 'https://example.com/$_installer',
        },
        {
          'name': 'TENVPN-0.2.0-windows-amd64.zip',
          'browser_download_url': 'https://example.com/w.zip',
        },
        {
          'name': checksumsAssetName,
          'browser_download_url': 'https://example.com/SHA256SUMS.txt',
        },
      ],
};

void main() {
  late Directory work;
  late List<(String, List<String>)> elevated;
  late List<Uri> downloads;

  setUp(() {
    work = Directory.systemTemp.createTempSync('tenvpn_update_test');
    elevated = [];
    downloads = [];
  });

  tearDown(() => work.deleteSync(recursive: true));

  WindowsUpdater updater({
    String? sums,
    List<int>? payload,
    bool accepted = true,
  }) => WindowsUpdater(
    fetchText: (url) async => sums ?? '$_hash  $_installer\n',
    download: (url, savePath, onProgress) async {
      downloads.add(url);
      final data = payload ?? _bytes;
      onProgress(data.length ~/ 2, data.length);
      await File(savePath).writeAsBytes(data);
      onProgress(data.length, data.length);
    },
    runInstaller: (executable, arguments) async {
      elevated.add((executable, arguments));
      return accepted ? 0 : 2;
    },
    workDir: () async => work.path,
  );

  group('UpdateRelease', () {
    test('picks the Windows installer and the checksums', () {
      final release = UpdateRelease.fromJson(_release())!;
      expect(release.version, '0.2.0');
      expect(release.installer!.name, _installer);
      expect(release.checksums!.url.path, '/SHA256SUMS.txt');
    });

    test('ignores non-https assets and missing tags', () {
      final release = UpdateRelease.fromJson(
        _release(
          assets: [
            {
              'name': _installer,
              'browser_download_url': 'http://example.com/$_installer',
            },
          ],
        ),
      )!;
      expect(release.installer, isNull);
      expect(UpdateRelease.fromJson({'assets': []}), isNull);
    });
  });

  test('checksumFor reads text and binary sha256sum lines', () {
    final sums = 'ABC  other.exe\n${_hash.toUpperCase()} *$_installer\r\n';
    expect(checksumFor(sums, _installer), _hash);
    expect(checksumFor(sums, 'missing.exe'), isNull);
  });

  test('verified installer runs silently and relaunches connected', () async {
    final progress = <double>[];
    await updater().install(
      UpdateRelease.fromJson(_release())!,
      reconnect: true,
      onProgress: progress.add,
    );
    expect(downloads.single.path, '/$_installer');
    expect(progress, [0.5, 1.0]);
    final (executable, arguments) = elevated.single;
    expect(File(executable).existsSync(), isTrue);
    expect(executable, endsWith(_installer));
    expect(arguments, [
      '/SILENT',
      '/SUPPRESSMSGBOXES',
      '/NORESTART',
      '/SP-',
      '/relaunch=--connect',
    ]);
  });

  test('without a running VPN the relaunch carries no arguments', () {
    expect(
      WindowsUpdater.installerArguments(reconnect: false),
      isNot(contains(startsWith('/relaunch'))),
    );
  });

  test('a corrupted download is deleted and never run', () async {
    await expectLater(
      updater(
        payload: [1, 2, 3],
      ).install(UpdateRelease.fromJson(_release())!, reconnect: false),
      throwsA(
        isA<UpdateException>().having(
          (e) => e.failure,
          'failure',
          UpdateFailure.broken,
        ),
      ),
    );
    expect(elevated, isEmpty);
    expect(File('${work.path}/update/$_installer').existsSync(), isFalse);
  });

  test('no checksum line for the installer means no install', () async {
    await expectLater(
      updater(
        sums: 'deadbeef  other\n',
      ).install(UpdateRelease.fromJson(_release())!, reconnect: false),
      throwsA(isA<UpdateException>()),
    );
    expect(downloads, isEmpty);
  });

  test('a release without an installer or checksums is refused', () async {
    final noInstaller = UpdateRelease.fromJson(_release(assets: []))!;
    await expectLater(
      updater().install(noInstaller, reconnect: false),
      throwsA(
        isA<UpdateException>().having(
          (e) => e.failure,
          'failure',
          UpdateFailure.noInstaller,
        ),
      ),
    );
  });

  test('a declined UAC prompt is reported', () async {
    await expectLater(
      updater(
        accepted: false,
      ).install(UpdateRelease.fromJson(_release())!, reconnect: false),
      throwsA(
        isA<UpdateException>().having(
          (e) => e.failure,
          'failure',
          UpdateFailure.declined,
        ),
      ),
    );
  });
}
