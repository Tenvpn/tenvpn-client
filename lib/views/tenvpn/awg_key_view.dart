import 'dart:async';
import 'dart:convert';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:fl_clash/tenvpn/tenvpn.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'main_view.dart' show tenvpnContentWidth;
import 'onboarding_view.dart' show tenvpnStore;
import 'state.dart';
import 'theme.dart';

/// AmneziaWG by a key from the cabinet: `vpn://…` or a `.conf`, kept on the
/// device and never sent anywhere. The key is a secret — it is not logged.
class TenvpnAwgKeyView extends ConsumerStatefulWidget {
  final bool playBuild;

  const TenvpnAwgKeyView({super.key, this.playBuild = tenvpnStore == 'play'});

  @override
  ConsumerState<TenvpnAwgKeyView> createState() => _TenvpnAwgKeyViewState();
}

class _TenvpnAwgKeyViewState extends ConsumerState<TenvpnAwgKeyView> {
  final _controller = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty) return;
    setState(() {
      _controller.text = text;
      _error = null;
    });
  }

  Future<void> _pickFile() async {
    final file = await globalState.safeRun(picker.pickerFile);
    if (file == null) return;
    final bytes = await file.readBytes();
    setState(() {
      _controller.text = utf8.decode(bytes, allowMalformed: true).trim();
      _error = null;
    });
  }

  String _message(Object error) {
    final l = context.appLocalizations;
    return switch (error) {
      AwgKeyException(error: AwgKeyError.empty) => l.tenvpnAwgKeyEmpty,
      AwgKeyException(error: AwgKeyError.unreadable) => l.tenvpnAwgKeyBroken,
      AwgKeyException(error: AwgKeyError.notAwg) => l.tenvpnAwgKeyNotAwg,
      _ => l.tenvpnAwgKeyInvalid,
    };
  }

  Future<void> _apply(String? conf) async {
    final profile = ref.read(currentProfileProvider);
    if (profile == null) return;
    setState(() => _busy = true);
    try {
      await ref.read(tenvpnConfigProvider).setManualAwg(profile.id, conf);
      await ref
          .read(profilesActionProvider.notifier)
          .regenerateProfile(profile);
      ref.read(tenvpnAwgKeyRefreshProvider.notifier).bump();
      if (mounted) Navigator.of(context).maybePop();
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final String conf;
    try {
      conf = decodeAwgKey(_controller.text);
    } on AwgKeyException catch (error) {
      setState(() => _error = _message(error));
      return;
    }
    await _apply(conf);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final p = context.palette;
    final hasKey = ref.watch(tenvpnManualAwgProvider).value ?? false;
    return Scaffold(
      appBar: AppBar(title: Text(l.tenvpnSectionReserve)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: tenvpnContentWidth),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              Text(
                l.tenvpnAwgKeyHint,
                style: TextStyle(fontSize: 14.5, height: 1.45, color: p.muted),
              ),
              if (!widget.playBuild)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const ValueKey('tenvpn-awg-cabinet'),
                    icon: const Icon(Symbols.open_in_new, size: 18),
                    label: Text(l.tenvpnOpenCabinet),
                    onPressed: () => unawaited(
                      launchUrl(
                        Uri.parse(tenvpnCabinetUrl),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('tenvpn-awg-key'),
                controller: _controller,
                enabled: !_busy,
                minLines: 4,
                maxLines: 8,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                style: TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 12,
                  color: p.text,
                ),
                decoration: InputDecoration(
                  hintText: 'vpn://…  /  [Interface]…',
                  filled: true,
                  fillColor: p.surface,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  key: const ValueKey('tenvpn-awg-key-error'),
                  style: TextStyle(fontSize: 13.5, color: p.danger),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TenvpnBigButton(
                      key: const ValueKey('tenvpn-awg-paste'),
                      label: l.tenvpnPaste,
                      primary: false,
                      height: 48,
                      onPressed: _busy ? null : _paste,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TenvpnBigButton(
                      key: const ValueKey('tenvpn-awg-file'),
                      label: l.tenvpnAwgKeyFile,
                      primary: false,
                      height: 48,
                      onPressed: _busy ? null : _pickFile,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TenvpnBigButton(
                key: const ValueKey('tenvpn-awg-save'),
                label: l.tenvpnConnect,
                loading: _busy,
                height: 54,
                onPressed: _save,
              ),
              if (hasKey) ...[
                const SizedBox(height: 10),
                TenvpnBigButton(
                  key: const ValueKey('tenvpn-awg-remove'),
                  label: l.tenvpnAwgKeyRemove,
                  primary: false,
                  height: 48,
                  onPressed: _busy ? null : () => _apply(null),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
