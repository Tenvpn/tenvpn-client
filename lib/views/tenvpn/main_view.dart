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
import 'package:url_launcher/url_launcher.dart';

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
                // A desktop window is resized freely; a button that tracked
                // its height made the whole screen swim.
                final button = system.isDesktop
                    ? 200.0
                    : [
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
      ConnectionPhase.off => ('', p.muted),
      ConnectionPhase.connecting => (l.tenvpnHintConnecting, p.muted),
      ConnectionPhase.on => (_ipText(context, ref, l), p.text),
      ConnectionPhase.error => (l.tenvpnHintError, p.danger),
    };
    // One line is always reserved, so turning on or off never shifts the
    // server list.
    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: double.infinity,
        minHeight: 22,
      ),
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

/// The one big control of the app: the ring and the icon say whether the
/// tunnel is up before any text is read — grey when off, a running lime arc
/// while connecting, a solid lime ring when on, red when there is no link.
class TenvpnPowerButton extends ConsumerWidget {
  final ConnectionPhase phase;
  final double size;

  const TenvpnPowerButton({super.key, required this.phase, this.size = 240});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.appLocalizations;
    final p = context.palette;
    final ring = size * 0.055;
    final (color, fill, label) = switch (phase) {
      ConnectionPhase.off => (p.muted, p.surface, l.tenvpnPowerOn),
      ConnectionPhase.connecting => (
        p.accentText,
        p.surface,
        l.tenvpnStatusConnecting,
      ),
      ConnectionPhase.on => (p.accentText, p.accentSoft, l.tenvpnPowerOnState),
      ConnectionPhase.error => (p.danger, p.dangerSoft, l.tenvpnStatusError),
    };
    final track = phase == ConnectionPhase.off ? p.elevated : color;
    return Semantics(
      button: true,
      label: phase == ConnectionPhase.off
          ? l.tenvpnConnect
          : l.tenvpnDisconnect,
      excludeSemantics: true,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.square(
              dimension: size,
              child: CircularProgressIndicator(
                key: ValueKey('tenvpn-ring-${phase.name}'),
                value: phase == ConnectionPhase.connecting ? null : 1,
                strokeWidth: ring,
                strokeCap: StrokeCap.round,
                color: track,
                backgroundColor: phase == ConnectionPhase.connecting
                    ? p.elevated
                    : Colors.transparent,
              ),
            ),
            Padding(
              padding: EdgeInsets.all(ring * 2),
              child: Material(
                color: fill,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  key: const ValueKey('tenvpn-connect'),
                  onTap: () =>
                      ref.read(commonActionProvider.notifier).toggleRunning(),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Symbols.power_settings_new,
                          size: size * 0.3,
                          color: color,
                          weight: 600,
                        ),
                        SizedBox(height: size * 0.03),
                        Text(
                          label,
                          style: TextStyle(
                            fontFamily: tenvpnDisplayFont,
                            fontWeight: FontWeight.w700,
                            fontSize: size * 0.085,
                            letterSpacing: -0.3,
                            color: phase == ConnectionPhase.off
                                ? p.text
                                : color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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

/// Paid-until (or the panel's end date), the balance when the backend sent
/// it, and «Продлить» — a secondary button: lime stays for "connected".
class TenvpnExpiryLine extends ConsumerWidget {
  const TenvpnExpiryLine({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.appLocalizations;
    final p = context.palette;
    final expiry = ref.watch(tenvpnExpiryProvider);
    final account = expiry.account;
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
    final money = NumberFormat.decimalPatternDigits(
      locale: locale,
      decimalDigits: 0,
    );
    return Column(
      children: [
        Text(
          text,
          key: const ValueKey('tenvpn-expiry'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: color),
        ),
        if (account != null && !expiry.free) ...[
          const SizedBox(height: 2),
          Text(
            [
              l.tenvpnBalance(
                money.format(account.balanceRub.floor()),
                money.format(account.dailyRateRub.round()),
              ),
              if (account.activeDevices > 0)
                l.tenvpnDevices(account.activeDevices),
            ].join(' · '),
            key: const ValueKey('tenvpn-balance'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: p.muted),
          ),
        ],
        const SizedBox(height: 6),
        OutlinedButton.icon(
          key: const ValueKey('tenvpn-renew'),
          onPressed: () => launchUrl(
            Uri.parse(ref.read(tenvpnRenewUrlProvider)),
            mode: LaunchMode.externalApplication,
          ),
          icon: const Icon(Symbols.add_card, size: 18),
          label: Text(l.tenvpnRenew),
          style: OutlinedButton.styleFrom(
            foregroundColor: p.text,
            side: BorderSide(color: p.borderStrong),
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }
}
