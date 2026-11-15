import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_maids/app.dart';
import 'package:golden_maids/core/constants/app_constants.dart';

void main() {
  testWidgets('App starts and shows the start screen', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: GoldenMaidsApp()));
    await tester.pumpAndSettle();

    expect(find.text(AppConstants.appName), findsOneWidget);
    expect(find.text(AppConstants.tagline), findsOneWidget);
  });
}
