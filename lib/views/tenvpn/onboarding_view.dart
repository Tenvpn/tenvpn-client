import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/tenvpn/tenvpn.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import 'main_view.dart';
import 'mascot.dart';
import 'theme.dart';

/// First run without a subscription, and «Вставить другую ссылку» later on
/// ([replace]): the new subscription then takes the place of the old one.
class TenvpnOnboardingView extends ConsumerStatefulWidget {
  final bool replace;

  const TenvpnOnboardingView({super.key, this.replace = false});

  @override
  ConsumerState<TenvpnOnboardingView> createState() =>
      _TenvpnOnboardingViewState();
}

class _TenvpnOnboardingViewState extends ConsumerState<TenvpnOnboardingView> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty || !mounted) return;
    _controller.text = text;
    setState(() => _error = null);
    await _submit();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final l = context.appLocalizations;
    final link = parseImportLink(_controller.text);
    if (link == null) {
      setState(() => _error = l.tenvpnBadLink);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final error = await ref
        .read(profilesActionProvider.notifier)
        .importSubscription(
          link.url,
          awg: link.awg,
          token: link.token,
          replace: widget.replace,
        );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
    });
    if (error == null && widget.replace) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final p = context.palette;
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.replace)
          const SizedBox(height: 56, child: Center(child: TenvpnLogo())),
        const Center(child: FerMascot(pose: FerPose.welcome, size: 230)),
        const SizedBox(height: 12),
        Text(
          l.tenvpnWelcomeTitle,
          style: context.textTheme.headlineMedium?.copyWith(fontSize: 28),
        ),
        const SizedBox(height: 8),
        Text(
          l.tenvpnWelcomeText,
          style: TextStyle(fontSize: 15, height: 1.45, color: p.muted),
        ),
        const SizedBox(height: 20),
        TextField(
          key: const ValueKey('tenvpn-link-field'),
          controller: _controller,
          enabled: !_busy,
          keyboardType: TextInputType.url,
          autocorrect: false,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 13.5,
            color: p.text,
          ),
          decoration: InputDecoration(
            labelText: l.tenvpnLinkLabel,
            hintText: 'https://…',
            filled: true,
            fillColor: p.surface,
            suffixIcon: IconButton(
              tooltip: l.tenvpnPaste,
              icon: const Icon(Symbols.content_paste),
              onPressed: _busy ? null : _paste,
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          _ErrorNote(text: _error!),
        ],
        const SizedBox(height: 16),
        TenvpnBigButton(
          key: const ValueKey('tenvpn-add'),
          label: l.tenvpnAdd,
          loading: _busy,
          onPressed: _submit,
        ),
        const SizedBox(height: 10),
        TenvpnBigButton(
          key: const ValueKey('tenvpn-open-bot'),
          label: l.tenvpnOpenBot,
          primary: false,
          height: 52,
          onPressed: () => unawaited(
            launchUrl(
              Uri.parse(tenvpnBotUrl),
              mode: LaunchMode.externalApplication,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            l.tenvpnNoLinkYet,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: p.mutedDeep),
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
    return Scaffold(
      appBar: widget.replace ? AppBar(title: Text(l.tenvpnChangeLink)) : null,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: tenvpnContentWidth),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: content,
            ),
          ),
        ),
      ),
    );
  }
}

class _ErrorNote extends StatelessWidget {
  final String text;

  const _ErrorNote({required this.text});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return DecoratedBox(
      key: const ValueKey('tenvpn-import-error'),
      decoration: ShapeDecoration(
        color: p.dangerSoft,
        shape: AppShape.md.copyWith(
          side: BorderSide(color: p.danger.withValues(alpha: 0.35)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Symbols.error, color: p.danger, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(fontSize: 13.5, height: 1.4, color: p.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
