import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/l10n/l10n.dart';
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

/// `play` for the Google Play build, `site` for the APK from the website.
const tenvpnStore = String.fromEnvironment(
  'TENVPN_STORE',
  defaultValue: 'site',
);

/// No subscription yet: four comic-strip steps that lead to the cabinet on
/// the site, then one «Вставить». With [replace] it takes the old one's place.
class TenvpnOnboardingView extends ConsumerStatefulWidget {
  final bool replace;
  final bool playBuild;

  const TenvpnOnboardingView({
    super.key,
    this.replace = false,
    this.playBuild = tenvpnStore == 'play',
  });

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
    void open(String url) => unawaited(
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
    );
    final steps = [
      _Step(
        number: 1,
        pose: (FerPose.welcome, 1),
        title: widget.playBuild ? l.tenvpnStep1Play : l.tenvpnStep1,
        text: widget.playBuild ? l.tenvpnStep1PlayText : l.tenvpnStep1Text,
        action: widget.playBuild
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TenvpnBigButton(
                    key: const ValueKey('tenvpn-open-cabinet'),
                    label: l.tenvpnOpen,
                    primary: false,
                    height: 36,
                    onPressed: () => open(tenvpnCabinetSiteUrl),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    cabinetInstallHint(l),
                    key: const ValueKey('tenvpn-cabinet-hint'),
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.3,
                      color: p.mutedDeep,
                    ),
                  ),
                ],
              ),
      ),
      _Step(
        number: 2,
        pose: (FerPose.connecting, 2),
        title: l.tenvpnStep2,
        text: l.tenvpnStep2Text,
      ),
      _Step(
        number: 3,
        pose: (FerPose.on, 3),
        title: l.tenvpnStep3,
        text: l.tenvpnStep3Text,
      ),
      _Step(
        number: 4,
        pose: (FerPose.welcome, 2),
        title: l.tenvpnStep4,
        text: l.tenvpnStep4Text,
        action: TenvpnBigButton(
          key: const ValueKey('tenvpn-paste'),
          label: l.tenvpnPaste,
          loading: _busy,
          height: 40,
          onPressed: _paste,
        ),
      ),
    ];
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.replace)
          const SizedBox(height: 56, child: Center(child: TenvpnLogo())),
        if (!widget.replace) ...[
          Text(
            l.tenvpnNoSubscription,
            key: const ValueKey('tenvpn-no-subscription'),
            style: context.textTheme.headlineMedium?.copyWith(fontSize: 26),
          ),
          const SizedBox(height: 6),
          Text(
            l.tenvpnNoSubscriptionText,
            style: TextStyle(fontSize: 15, height: 1.45, color: p.muted),
          ),
          const SizedBox(height: 16),
        ],
        for (final row in [steps.sublist(0, 2), steps.sublist(2)]) ...[
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: row[0]),
                const SizedBox(width: 10),
                Expanded(child: row[1]),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (_error != null) ...[
          const SizedBox(height: 2),
          _ErrorNote(text: _error!),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 8),
        Text(p.caps(l.tenvpnOrManual), style: p.captionStyle(p.muted)),
        const SizedBox(height: 8),
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
          ),
        ),
        const SizedBox(height: 12),
        TenvpnBigButton(
          key: const ValueKey('tenvpn-add'),
          label: l.tenvpnAdd,
          primary: false,
          loading: _busy,
          height: 50,
          onPressed: _submit,
        ),
        if (widget.playBuild) ...[
          const SizedBox(height: 14),
          Center(
            child: Text(
              l.tenvpnProviderHint,
              key: const ValueKey('tenvpn-provider-hint'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: p.mutedDeep),
            ),
          ),
        ] else
          Center(
            child: TextButton(
              key: const ValueKey('tenvpn-bot-fallback'),
              onPressed: () => open(tenvpnBotUrl),
              child: Text(
                l.tenvpnBotFallback,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: p.muted),
              ),
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

String cabinetInstallHint(AppLocalizations l) =>
    system.isDesktop ? l.tenvpnCabinetHintDesktop : l.tenvpnCabinetHint;

/// One square of the comic: Fer (or a big number in «Строгий»), a short
/// caption and, for the first and the last step, the action itself.
class _Step extends StatelessWidget {
  final int number;
  final (FerPose, int) pose;
  final String title;
  final String text;
  final Widget? action;

  const _Step({
    required this.number,
    required this.pose,
    required this.title,
    required this.text,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final picture = p.showMascot
        ? Image.asset(
            ferAsset(pose.$1, pose.$2),
            height: 86,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const SizedBox(height: 86),
          )
        : SizedBox(
            height: 52,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '$number',
                style: TextStyle(
                  fontFamily: tenvpnDisplayFont,
                  fontWeight: FontWeight.w800,
                  fontSize: 40,
                  height: 1,
                  color: number == 4 ? p.accentText : p.text,
                ),
              ),
            ),
          );
    return TenvpnCard(
      key: ValueKey('tenvpn-step-$number'),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              Center(child: picture),
              if (p.showMascot)
                Text(
                  '$number',
                  style: TextStyle(
                    fontFamily: tenvpnDisplayFont,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: p.accentText,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            p.caps(title),
            style: p.strict
                ? p.captionStyle(p.text).copyWith(fontSize: 12)
                : TextStyle(
                    fontFamily: tenvpnDisplayFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    height: 1.2,
                    color: p.text,
                  ),
          ),
          const SizedBox(height: 4),
          Text(
            text,
            style: TextStyle(fontSize: 12.5, height: 1.35, color: p.muted),
          ),
          if (action != null) ...[
            const Spacer(),
            const SizedBox(height: 10),
            action!,
          ],
        ],
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
