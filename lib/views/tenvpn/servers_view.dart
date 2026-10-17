import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/tenvpn/tenvpn.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'main_view.dart' show TenvpnPing;
import 'state.dart';
import 'theme.dart';

/// The server choice, inline under the power button: compact one-line rows,
/// the main servers open, the special sections folded so the list stays
/// short. Speeds are measured once the manual group shows up and again on
/// request.
class TenvpnServerList extends ConsumerStatefulWidget {
  const TenvpnServerList({super.key});

  @override
  ConsumerState<TenvpnServerList> createState() => _TenvpnServerListState();
}

class _TenvpnServerListState extends ConsumerState<TenvpnServerList> {
  bool _measured = false;
  final _opened = <ServerSectionKind>{};

  @override
  void initState() {
    super.initState();
    ref.listenManual(
      groupsProvider.select((groups) => groups.getGroup(manualGroupName)),
      (_, manual) {
        if (manual != null && !_measured) {
          _measured = true;
          WidgetsBinding.instance.addPostFrameCallback((_) => _checkSpeed());
        }
      },
      fireImmediately: true,
    );
  }

  void _checkSpeed() {
    if (!mounted) return;
    final manual = ref.read(groupsProvider).getGroup(manualGroupName);
    if (manual == null) return;
    unawaited(
      ref.read(proxiesActionProvider.notifier).delayTestGroups([manual]),
    );
  }

  void _select(String? server) {
    unawaited(
      ref.read(proxiesActionProvider.notifier).selectTenvpnServer(server),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final p = context.palette;
    final sections = ref.watch(tenvpnSectionsProvider);
    final selection = ref.watch(tenvpnSelectionProvider);
    final active = ref.watch(tenvpnPhaseProvider) == ConnectionPhase.on;
    final look = ref.watch(
      appSettingProvider.select((s) => (s.serverListStyle, s.serverSort)),
    );
    final detailed = look.$1 == ServerListStyle.detailed;
    final testUrl = ref.watch(
      groupsProvider.select((g) => g.getGroup(manualGroupName)?.testUrl),
    );
    List<ServerPresentation> ordered(List<ServerPresentation> servers) =>
        look.$2 == ServerSort.ping
        ? sortByPing(
            servers,
            (name) =>
                ref.watch(delayProvider(proxyName: name, testUrl: testUrl)),
          )
        : servers;
    bool isSelected(ServerPresentation s) =>
        !selection.auto && selection.server == s.name;
    Widget tile(ServerPresentation server) => _ServerTile(
      server: server,
      selected: isSelected(server),
      active: active,
      detailed: detailed,
      onTap: () => _select(server.name),
    );
    bool isOpen(ServerSection section) =>
        detailed ||
        _opened.contains(section.kind) ||
        section.servers.any(isSelected);
    final main = ordered([
      for (final s in sections)
        if (s.kind == ServerSectionKind.main) ...s.servers,
    ]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  l.tenvpnServers,
                  style: TextStyle(
                    fontFamily: tenvpnDisplayFont,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                    color: p.text,
                  ),
                ),
              ),
            ),
            _PingButton(onPressed: _checkSpeed),
          ],
        ),
        const SizedBox(height: 8),
        _Group(
          children: [
            _AutoTile(
              selected: selection.auto,
              active: active,
              detailed: detailed,
              current: selection.auto ? selection.server : null,
              onTap: () => _select(null),
            ),
            ...main.map(tile),
          ],
        ),
        for (final section in sections)
          if (section.kind != ServerSectionKind.main) ...[
            const SizedBox(height: 10),
            _Group(
              children: [
                _SectionHeader(
                  kind: section.kind,
                  count: section.servers.length,
                  open: isOpen(section),
                  onTap: () => setState(() {
                    if (!_opened.remove(section.kind)) {
                      _opened.add(section.kind);
                    }
                  }),
                ),
                if (isOpen(section)) ...ordered(section.servers).map(tile),
              ],
            ),
          ],
      ],
    );
  }
}

class _PingButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _PingButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Material(
      color: p.elevated,
      shape: AppShape.full,
      child: InkWell(
        key: const ValueKey('tenvpn-ping'),
        customBorder: AppShape.full,
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Symbols.refresh, size: 16, color: p.muted),
              const SizedBox(width: 6),
              Text(
                context.appLocalizations.tenvpnCheckSpeed,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: p.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Group extends StatelessWidget {
  final List<Widget> children;

  const _Group({required this.children});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return TenvpnCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 52, color: p.border),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final Widget leading;
  final Widget title;
  final Widget? trailing;
  final Widget end;
  final VoidCallback onTap;
  final double minHeight;

  const _Row({
    super.key,
    required this.leading,
    required this.title,
    this.trailing,
    required this.end,
    required this.onTap,
    this.minHeight = 50,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
          child: Row(
            children: [
              SizedBox(width: 28, child: Center(child: leading)),
              const SizedBox(width: 12),
              Expanded(child: title),
              ?trailing,
              const SizedBox(width: 8),
              end,
            ],
          ),
        ),
      ),
    );
  }
}

class _AutoTile extends StatelessWidget {
  final bool selected;
  final bool active;
  final bool detailed;
  final String? current;
  final VoidCallback onTap;

  const _AutoTile({
    required this.selected,
    required this.active,
    required this.detailed,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final p = context.palette;
    final now = current == null
        ? null
        : presentServer(name: current!, type: '');
    return _Row(
      key: const ValueKey('tenvpn-server-auto'),
      onTap: onTap,
      leading: Icon(Symbols.bolt, color: p.cocoaText, size: 24, fill: 1),
      minHeight: detailed ? 60 : 50,
      title: _Line(
        detailed: detailed,
        title: l.tenvpnAuto,
        detail: now == null
            ? l.tenvpnAutoDesc
            : l.tenvpnNow('${now.flag} ${now.title}'.trim()),
      ),
      end: _Check(selected: selected, active: active),
    );
  }
}

/// One line: the title, then a muted detail that is the first to be cut
/// with an ellipsis when the row is narrow.
class _Line extends StatelessWidget {
  final String title;
  final String detail;
  final bool detailed;

  const _Line({
    required this.title,
    required this.detail,
    this.detailed = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (detailed) {
      const fallback = ['Twemoji'];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
              color: p.text,
              fontFamilyFallback: fallback,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              color: p.muted,
              fontFamilyFallback: fallback,
            ),
          ),
        ],
      );
    }
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: title,
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w500,
              color: p.text,
            ),
          ),
          TextSpan(
            text: '   $detail',
            style: TextStyle(fontSize: 12.5, color: p.mutedDeep),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontFamilyFallback: ['Twemoji']),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final ServerSectionKind kind;
  final int count;
  final bool open;
  final VoidCallback onTap;

  const _SectionHeader({
    required this.kind,
    required this.count,
    required this.open,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.appLocalizations;
    final p = context.palette;
    final (icon, title, description) = switch (kind) {
      ServerSectionKind.main => (Symbols.public, l.tenvpnSectionMain, ''),
      ServerSectionKind.mobile => (
        Symbols.signal_cellular_alt,
        l.tenvpnSectionMobile,
        l.tenvpnSectionMobileDesc,
      ),
      ServerSectionKind.reserve => (
        Symbols.shield,
        l.tenvpnSectionReserve,
        l.tenvpnSectionReserveDesc,
      ),
    };
    return _Row(
      key: ValueKey('tenvpn-section-${kind.name}'),
      onTap: onTap,
      leading: Icon(icon, color: p.muted, size: 22),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$title · $count',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: p.text,
            ),
          ),
          Text(
            description,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: p.mutedDeep),
          ),
        ],
      ),
      end: AnimatedRotation(
        turns: open ? 0.5 : 0,
        duration: const Duration(milliseconds: 200),
        child: Icon(Symbols.expand_more, color: p.muted),
      ),
    );
  }
}

class _ServerTile extends StatelessWidget {
  final ServerPresentation server;
  final bool selected;
  final bool active;
  final bool detailed;
  final VoidCallback onTap;

  const _ServerTile({
    required this.server,
    required this.selected,
    required this.active,
    required this.detailed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tags = [
      if (server.tags.contains(ServerTag.youtube)) 'YouTube',
      if (server.tags.contains(ServerTag.gemini)) 'Gemini',
    ];
    return _Row(
      key: ValueKey('tenvpn-server-${server.name}'),
      onTap: onTap,
      leading: EmojiText(
        server.flag.isNotEmpty
            ? server.flag
            : server.section == ServerSectionKind.reserve
            ? '🛡'
            : '🌐',
        style: TextStyle(fontSize: detailed ? 24 : 20),
      ),
      minHeight: detailed ? 60 : 50,
      title: _Line(
        detailed: detailed,
        title: server.title,
        detail: [server.protocol, ...tags].join(' · '),
      ),
      trailing: TenvpnPing(proxyName: server.name),
      end: _Check(selected: selected, active: active),
    );
  }
}

/// Selection mark: cream while the tunnel is off, lime only once it works —
/// lime means «работает» everywhere in the brandbook.
class _Check extends StatelessWidget {
  final bool selected;
  final bool active;

  const _Check({required this.selected, required this.active});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (!selected) {
      return Icon(Symbols.circle, color: p.borderStrong, size: 22);
    }
    return Icon(
      Symbols.check_circle,
      fill: 1,
      size: 22,
      color: active ? p.accentText : p.text,
    );
  }
}
