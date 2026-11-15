import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_maids/app.dart';
import 'package:golden_maids/core/constants/app_constants.dart';
import 'package:golden_maids/core/widgets/app_logo.dart';

void main() {
  testWidgets('App starts and shows the design preview', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: GoldenMaidsApp()));
    // The preview contains looping shimmer animations, so pump a fixed time
    // instead of waiting for all animations to settle.
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Design System'), findsOneWidget);
    expect(find.text(AppConstants.appName), findsOneWidget);
    expect(find.byType(AppLogo), findsWidgets);
    // Tests run without env.json, so the backend card reports that.
    expect(find.text('Backend: not configured'), findsOneWidget);
  });
}
