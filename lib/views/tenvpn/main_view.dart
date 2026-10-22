import 'dart:ui' show ImageFilter;

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/l10n/l10n.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/tenvpn/tenvpn.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'mascot.dart';
import 'servers_view.dart';
import 'settings_view.dart';
import 'state.dart';
import 'theme.dart';

const tenvpnContentWidth = 460.0;

class TenvpnMainView extends ConsumerWidget {
  const TenvpnMainView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final phase = ref.watch(tenvpnPhaseProvider);
    // The url-test group can move to another exit on its own; the base only
    // re-checks the IP on manual switches, so «Ваш IP» would stay stale.
    ref.listen(tenvpnSelectionProvider.select((s) => s.server), (prev, next) {
      if (prev != null && prev != next && ref.read(isStartProvider)) {
        ref.read(checkIpNumProvider.notifier).add();
      }
    });
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: tenvpnContentWidth),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final button = [
                  constraints.maxHeight * 0.3,
                  constraints.maxWidth * 0.62,
                ].reduce((a, b) => a < b ? a : b).clamp(140.0, 250.0);
                return ListView(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    0,
                    16,
                    24 + MediaQuery.paddingOf(context).bottom,
                  ),
                  children: [
                    const _TopBar(),
                    const SizedBox(height: 4),
                    Center(
                      child: TenvpnPowerButton(phase: phase, size: button),
                    ),
                    const SizedBox(height: 14),
                    _StatusHint(phase: phase),
                    const SizedBox(height: 6),
                    const TenvpnExpiryLine(),
                    const SizedBox(height: 18),
                    const TenvpnServerList(),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class TenvpnLogo extends StatelessWidget {
  final double size;

  const TenvpnLogo({super.key, this.size = 20});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final style = TextStyle(
      fontFamily: tenvpnDisplayFont,
      fontWeight: FontWeight.w800,
      fontSize: size,
      letterSpacing: -0.03 * size,
      color: p.text,
    );
    return Text.rich(
      TextSpan(
        children: [
          const TextSpan(text: 'TEN'),
          TextSpan(
            text: 'VPN',
            style: TextStyle(color: p.accentText),
          ),
        ],
      ),
      style: style,
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          const TenvpnLogo(),
          const Spacer(),
          IconButton(
            tooltip: context.appLocalizations.tenvpnSettings,
            icon: const Icon(Symbols.settings),
            onPressed: () =>
                BaseNavigator.push(context, const TenvpnSettingsView()),
          ),
        ],
      ),
    );
  }
}

class _StatusHint extends ConsumerWidget {
  final ConnectionPhase phase;

  const _StatusHint({required this.phase});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.appLocalizations;
    final p = context.palette;
    final (hint, color) = switch (phase) {
      ConnectionPhase.off => (l.tenvpnHintOff, p.muted),
      ConnectionPhase.connecting => (l.tenvpnHintConnecting, p.muted),
      ConnectionPhase.on => (_ipText(context, ref, l), p.text),
      ConnectionPhase.error => (l.tenvpnHintError, p.danger),
    };
    return SizedBox(
      width: double.infinity,
      child: EmojiText(
        hint,
        key: const ValueKey('tenvpn-status-hint'),
        maxLines: 2,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 15.5, height: 1.4, color: color),
      ),
    );
  }

  String _ipText(BuildContext context, WidgetRef ref, AppLocalizations l) {
    final ip = ref.watch(tenvpnIpProvider);
    if (ip == null) return l.tenvpnHintOn;
    final russian = Localizations.localeOf(context).languageCode == 'ru';
    final country =
        '${flagEmoji(ip.countryCode)} '
        '${countryName(ip.countryCode, russian: russian)}';
    return l.tenvpnYourIp(country.trim());
  }
}

/// The one big control of the app. «С хорьком» puts Fer inside the ring and
/// the status under it; «Строгий» is a thin ring with everything inside.
/// «Защищено» and the session timer appear only once the tunnel is checked.
class TenvpnPowerButton extends ConsumerWidget {
  final ConnectionPhase phase;
  final double size;

  const TenvpnPowerButton({super.key, required this.phase, this.size = 240});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.appLocalizations;
    final p = context.palette;
    final on = phase == ConnectionPhase.on;
    final label = switch (phase) {
      ConnectionPhase.off => l.tenvpnPowerOn,
      ConnectionPhase.connecting => l.tenvpnStatusConnecting,
      ConnectionPhase.on => l.tenvpnPowerOnState,
      ConnectionPhase.error => l.tenvpnStatusError,
    };
    final color = switch (phase) {
      ConnectionPhase.off => p.strict ? p.borderStrong : p.muted,
      ConnectionPhase.connecting || ConnectionPhase.on => p.accentText,
      ConnectionPhase.error => p.danger,
    };
    final chip = _StatusChip(
      label: switch (phase) {
        ConnectionPhase.off => l.tenvpnChipOff,
        ConnectionPhase.on => l.tenvpnChipProtected,
        _ => l.tenvpnChipUnprotected,
      },
      color: switch (phase) {
        ConnectionPhase.on => p.accentText,
        ConnectionPhase.error => p.danger,
        _ => p.muted,
      },
    );
    final runTime = on ? ref.watch(runTimeProvider) : null;
    final timer = runTime == null
        ? null
        : Text(
            getTimeText(runTime),
            key: const ValueKey('tenvpn-session-timer'),
            style: TextStyle(
              fontSize: p.strict ? size * 0.06 : 15,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: p.muted,
            ),
          );
    final labelStyle = TextStyle(
      fontFamily: tenvpnDisplayFont,
      fontWeight: p.strict ? FontWeight.w800 : FontWeight.w700,
      fontSize: p.strict ? size * 0.08 : 19,
      letterSpacing: p.strict ? 1.2 : -0.3,
      color: phase == ConnectionPhase.off ? p.text : color,
    );
    void toggle() => ref.read(commonActionProvider.notifier).toggleRunning();
    final ringSize = p.strict ? size : size * 0.8;
    final ring = _Ring(
      phase: phase,
      size: ringSize,
      color: color,
      width: switch ((p.strict, on || phase == ConnectionPhase.error)) {
        (true, true) => 2.5,
        (true, false) => 1.5,
        (false, true) => 3.5,
        (false, false) => 2,
      },
      onTap: toggle,
      child: p.strict
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                chip,
                SizedBox(height: size * 0.04),
                Icon(
                  Symbols.power_settings_new,
                  size: size * 0.18,
                  color: color,
                  weight: 300,
                ),
                SizedBox(height: size * 0.025),
                Text(p.caps(label), style: labelStyle),
                if (timer != null) ...[SizedBox(height: size * 0.02), timer],
              ],
            )
          : ClipOval(
              child: FerMascot(pose: ferPoseFor(phase), size: ringSize * 0.86),
            ),
    );
    return Semantics(
      button: true,
      label: phase == ConnectionPhase.off
          ? l.tenvpnConnect
          : l.tenvpnDisconnect,
      excludeSemantics: true,
      child: p.strict
          ? ring
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ring,
                const SizedBox(height: 12),
                chip,
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: toggle,
                  child: Text(label, style: labelStyle),
                ),
                if (timer != null) ...[const SizedBox(height: 2), timer],
              ],
            ),
    );
  }
}

class _Ring extends StatelessWidget {
  final ConnectionPhase phase;
  final double size;
  final Color color;
  final double width;
  final VoidCallback onTap;
  final Widget child;

  const _Ring({
    required this.phase,
    required this.size,
    required this.color,
    required this.width,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final connecting = phase == ConnectionPhase.connecting;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (phase == ConnectionPhase.on)
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
              child: SizedBox.square(
                dimension: size,
                child: CircularProgressIndicator(
                  value: 1,
                  strokeWidth: width * 3,
                  color: p.accent.withValues(alpha: 0.45),
                ),
              ),
            ),
          SizedBox.square(
            dimension: size,
            child: CircularProgressIndicator(
              key: ValueKey('tenvpn-ring-${phase.name}'),
              value: connecting ? null : 1,
              strokeWidth: width,
              strokeCap: StrokeCap.round,
              color: color,
              backgroundColor: connecting ? p.border : Colors.transparent,
            ),
          ),
          Material(
            color: Colors.transparent,
            shape: const CircleBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              key: const ValueKey('tenvpn-connect'),
              onTap: onTap,
              child: SizedBox.square(
                dimension: size - width * 4,
                child: Center(child: child),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return DecoratedBox(
      key: const ValueKey('tenvpn-status-chip'),
      decoration: ShapeDecoration(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(p.strict ? 4 : 20)),
          side: BorderSide(color: color.withValues(alpha: 0.7)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(9, 4, 10, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              child: const SizedBox.square(dimension: 6),
            ),
            const SizedBox(width: 6),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontFamily: tenvpnDisplayFont,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.3,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TenvpnPing extends ConsumerWidget {
  final String proxyName;

  const TenvpnPing({super.key, required this.proxyName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final testUrl = ref
        .watch(groupsProvider)
        .getGroup(manualGroupName)
        ?.testUrl;
    final delay = ref.watch(
      delayProvider(proxyName: proxyName, testUrl: testUrl),
    );
    final pending = ref.watch(
      delayTestPendingProvider(proxyName: proxyName, testUrl: testUrl),
    );
    final style = TextStyle(
      fontFamily: 'JetBrainsMono',
      fontSize: 12.5,
      color: delay != null && delay < 0 ? p.danger : p.muted,
    );
    final Widget child;
    if (pending || delay == 0) {
      child = SizedBox.square(
        dimension: 14,
        child: CircularProgressIndicator(strokeWidth: 1.8, color: p.muted),
      );
    } else if (delay == null) {
      child = const SizedBox.shrink();
    } else {
      child = Text(
        delay > 0
            ? context.appLocalizations.tenvpnMs(delay)
            : context.appLocalizations.tenvpnNoReply,
        style: style,
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: child,
    );
  }
}

/// How long the subscription lasts — and nothing about paying for it: the app
/// is a connector, the account lives in the bot (owner's call, 17.10).
class TenvpnExpiryLine extends ConsumerWidget {
  const TenvpnExpiryLine({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.appLocalizations;
    final p = context.palette;
    final expiry = ref.watch(tenvpnExpiryProvider);
    final locale = Localizations.localeOf(context).toLanguageTag();
    var color = p.muted;
    final String text;
    final date = expiry.date;
    if (expiry.free) {
      text = l.tenvpnFreeAccess;
    } else if (expiry.suspended) {
      text = l.tenvpnSuspended;
      color = p.danger;
    } else if (date == null) {
      text = l.tenvpnExpiresUnknown;
    } else {
      final left = daysLeft(date, DateTime.now());
      final formatted = DateFormat.yMMMMd(locale).format(date);
      if (left < 0) {
        text = l.tenvpnExpired;
        color = p.danger;
      } else {
        final head = expiry.source == ExpirySource.account
            ? l.tenvpnPaidUntil(formatted)
            : l.tenvpnExpires(formatted);
        text = '$head · ${l.tenvpnDaysLeft(left)}';
        if (left <= 3) color = p.warn;
      }
    }
    return Text(
      text,
      key: const ValueKey('tenvpn-expiry'),
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 13, color: color),
    );
  }
}
