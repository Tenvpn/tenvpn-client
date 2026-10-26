import 'package:fl_clash/views/tenvpn/onboarding_view.dart';
import 'package:fl_clash/views/tenvpn/theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../helpers/test_app.dart';

Widget _onboarding({required bool playBuild}) => ProviderScope(
  child: TestApp(
    child: Theme(
      data: buildTenvpnTheme(brightness: Brightness.dark),
      child: TenvpnOnboardingView(playBuild: playBuild),
    ),
  ),
);

void main() {
  testWidgets('onboarding is only the link field, like a connector', (
    tester,
  ) async {
    await tester.pumpWidget(_onboarding(playBuild: false));
    await tester.pump();

    expect(find.byKey(const ValueKey('tenvpn-link-field')), findsOneWidget);
    expect(find.byKey(const ValueKey('tenvpn-add')), findsOneWidget);
    expect(find.byKey(const ValueKey('tenvpn-open-bot')), findsNothing);
    expect(find.text('Open the bot'), findsNothing);
    expect(find.byKey(const ValueKey('tenvpn-provider-hint')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('the Play build says where the link comes from, no links', (
    tester,
  ) async {
    await tester.pumpWidget(_onboarding(playBuild: true));
    await tester.pump();

    expect(
      find.text('You get the subscription link from your TENVPN provider'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('tenvpn-open-bot')), findsNothing);
    expect(find.textContaining('t.me'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  test('the website build is the default', () {
    expect(tenvpnStore, 'site');
  });
}
