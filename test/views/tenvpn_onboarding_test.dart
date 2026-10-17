import 'package:fl_clash/views/tenvpn/onboarding_view.dart';
import 'package:fl_clash/views/tenvpn/theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

void main() {
  testWidgets('onboarding is only the link field, like a connector', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        child: TestApp(
          child: Theme(
            data: buildTenvpnTheme(brightness: Brightness.dark),
            child: const TenvpnOnboardingView(),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('tenvpn-link-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('tenvpn-add')), findsOneWidget);
    expect(find.byKey(const ValueKey('tenvpn-open-bot')), findsNothing);
    expect(find.text('Open the bot'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
