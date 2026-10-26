import 'package:fl_clash/pages/home.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'account_tasks.dart';
import 'main_view.dart';
import 'mascot.dart';
import 'network_mode_tasks.dart';
import 'onboarding_view.dart';

/// The app's home: onboarding until there is a subscription, then the one
/// button. Everything else is pushed on top of it.
class TenvpnHome extends ConsumerWidget {
  const TenvpnHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loaded = ref.watch(profilesStreamProvider.select((v) => v.hasValue));
    final hasProfile = ref.watch(
      profilesProvider.select((profiles) => profiles.isNotEmpty),
    );
    final Widget child;
    if (!loaded) {
      child = const TenvpnSplash(key: ValueKey('tenvpn-loading'));
    } else if (hasProfile) {
      child = const TenvpnAccountTasks(
        key: ValueKey('tenvpn-main'),
        child: TenvpnNetworkModeTasks(child: TenvpnMainView()),
      );
    } else {
      child = const TenvpnOnboardingView(key: ValueKey('tenvpn-onboarding'));
    }
    return HomeBackScopeContainer(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: child,
      ),
    );
  }
}

class TenvpnSplash extends StatelessWidget {
  const TenvpnSplash({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FerMascot(pose: FerPose.connecting, size: 220),
            SizedBox(height: 16),
            TenvpnLogo(size: 26),
          ],
        ),
      ),
    );
  }
}
