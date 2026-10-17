import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/views/config/advanced.dart';
import 'package:fl_clash/views/hotkey.dart';
import 'package:fl_clash/views/views.dart';
import 'package:fl_clash/widgets/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

/// Everything the base client can do, one tap away from people who need it
/// and out of the way of everyone else.
class TenvpnAdvancedView extends ConsumerWidget {
  const TenvpnAdvancedView({super.key});

  Widget _page(PageLabel label, IconData icon, Widget view) {
    final description = label.description;
    return ListItem.open(
      leading: Icon(icon),
      title: Text(label.label),
      subtitle: description == null ? null : Text(description),
      widget: view,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.appLocalizations;
    final developerMode = ref.watch(
      appSettingProvider.select((state) => state.developerMode),
    );
    return CommonScaffold(
      title: l.tenvpnAdvanced,
      body: ListView(
        padding: sectionPagePadding,
        children: [
          generateSectionV3(
            title: l.more,
            isFirst: true,
            items: [
              _page(PageLabel.profiles, Symbols.folder, const ProfilesView()),
              _page(PageLabel.proxies, Symbols.article, const ProxiesView()),
              _page(
                PageLabel.connections,
                Symbols.ballot,
                const ConnectionsView(),
              ),
              _page(
                PageLabel.requests,
                Symbols.view_timeline,
                const RequestsView(),
              ),
              _page(PageLabel.dnsQueries, Symbols.dns, const DnsQueriesView()),
              _page(PageLabel.logs, Symbols.adb, const LogsView()),
              _page(
                PageLabel.resources,
                Symbols.home_storage,
                const ResourcesView(),
              ),
            ],
          ),
          generateSectionV3(
            title: l.settings,
            items: [
              ListItem.open(
                leading: const Icon(Symbols.settings),
                title: Text(l.general),
                subtitle: Text(l.generalDesc),
                widget: const GeneralView(),
              ),
              ListItem.open(
                leading: const Icon(Symbols.build),
                title: Text(l.advancedConfig),
                subtitle: Text(l.advancedConfigDesc),
                widget: const AdvancedConfigView(),
              ),
              if (system.isDesktop)
                ListItem.open(
                  leading: const Icon(Symbols.keyboard),
                  title: Text(l.hotkeyManagement),
                  subtitle: Text(l.hotkeyManagementDesc),
                  widget: const HotKeyView(),
                ),
              ListItem.open(
                leading: const Icon(Symbols.cloud_sync),
                title: Text(l.backupAndRestore),
                subtitle: Text(l.backupAndRestoreDesc),
                widget: const BackupAndRestore(),
              ),
              if (developerMode)
                ListItem.open(
                  leading: const Icon(Symbols.developer_board),
                  title: Text(l.developerMode),
                  widget: const DeveloperView(),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
