import 'dart:async';

import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/providers.dart';
import 'package:fl_clash/state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import 'onboarding_view.dart';
import 'theme.dart';

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String text,
  required String action,
}) async {
  final l = context.appLocalizations;
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(text),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l.cancel),
        ),
        TextButton(
          key: const ValueKey('tenvpn-confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(action),
        ),
      ],
    ),
  );
  return yes ?? false;
}

void refreshSubscription(WidgetRef ref) {
  final profile = ref.read(currentProfileProvider);
  if (profile == null) return;
  unawaited(
    globalState.safeRun(
      () => ref
          .read(profilesActionProvider.notifier)
          .updateProfile(profile, showLoading: true),
    ),
  );
}

/// One subscription at a time: a new one replaces the old, after a warning.
Future<void> takeAnotherSubscription(BuildContext context) async {
  final l = context.appLocalizations;
  final yes = await _confirm(
    context,
    title: l.tenvpnReplaceTitle,
    text: l.tenvpnReplaceText,
    action: l.tenvpnReplace,
  );
  if (!yes || !context.mounted) return;
  await BaseNavigator.push(context, const TenvpnOnboardingView(replace: true));
}

Future<void> deleteSubscription(BuildContext context, WidgetRef ref) async {
  final l = context.appLocalizations;
  final profile = ref.read(currentProfileProvider);
  if (profile == null) return;
  final yes = await _confirm(
    context,
    title: l.tenvpnDeleteTitle,
    text: l.tenvpnDeleteText,
    action: l.delete,
  );
  if (!yes) return;
  await ref.read(profilesActionProvider.notifier).deleteProfile(profile.id);
  if (context.mounted) {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}

Future<void> showSubscriptionMenu(BuildContext context, WidgetRef ref) {
  final l = context.appLocalizations;
  final p = context.palette;
  Widget item(IconData icon, String title, String key, VoidCallback onTap) =>
      ListTile(
        key: ValueKey(key),
        leading: Icon(icon, color: p.cocoaText),
        title: Text(title),
        onTap: () {
          Navigator.of(context).pop();
          onTap();
        },
      );
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          item(
            Symbols.sync,
            l.tenvpnUpdateSubscription,
            'tenvpn-menu-refresh',
            () => refreshSubscription(ref),
          ),
          item(
            Symbols.swap_horiz,
            l.tenvpnChangeLink,
            'tenvpn-menu-replace',
            () => unawaited(takeAnotherSubscription(context)),
          ),
          item(
            Symbols.delete,
            l.tenvpnDeleteSubscription,
            'tenvpn-menu-delete',
            () => unawaited(deleteSubscription(context, ref)),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

bool subscriptionUpdating(WidgetRef ref, Profile? profile) =>
    profile != null && ref.watch(isUpdatingProvider(profile.updatingKey));
