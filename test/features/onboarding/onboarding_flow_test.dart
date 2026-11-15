import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_maids/app.dart';
import 'package:golden_maids/core/services/shared_preferences_provider.dart';
import 'package:golden_maids/features/onboarding/data/onboarding_repository.dart';
import 'package:golden_maids/features/onboarding/domain/onboarding_page.dart';
import 'package:golden_maids/features/onboarding/presentation/splash_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SharedPreferences> _preferences(Map<String, Object> values) {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

Future<void> _startApp(WidgetTester tester, SharedPreferences prefs) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const GoldenMaidsApp(),
    ),
  );
}

/// Lets the splash finish and the next screen appear.
Future<void> _passSplash(WidgetTester tester) async {
  await tester.pump(SplashScreen.displayTime);
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  testWidgets('first launch: splash shows the brand, then onboarding', (
    tester,
  ) async {
    final prefs = await _preferences({});
    await _startApp(tester, prefs);

    expect(find.text('Golden Maids'), findsOneWidget);
    expect(find.text('Professional Care. Trusted Homes.'), findsOneWidget);

    await _passSplash(tester);
    expect(find.text(onboardingPages[0].title), findsOneWidget);
  });

  testWidgets('returning signed-out user skips onboarding to Welcome', (
    tester,
  ) async {
    final prefs = await _preferences({OnboardingRepository.seenKey: true});
    await _startApp(tester, prefs);
    await _passSplash(tester);

    expect(find.text(onboardingPages[0].title), findsNothing);
    expect(find.text('Welcome to Golden Maids'), findsOneWidget);
  });

  testWidgets('Next moves through the pages; last page shows Get Started', (
    tester,
  ) async {
    final prefs = await _preferences({});
    await _startApp(tester, prefs);
    await _passSplash(tester);

    expect(find.text('Get Started'), findsNothing);

    await tester.tap(find.byTooltip('Next'));
    await tester.pumpAndSettle();
    expect(find.text(onboardingPages[1].title), findsOneWidget);

    await tester.tap(find.byTooltip('Next'));
    await tester.pumpAndSettle();
    expect(find.text(onboardingPages[2].title), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
    expect(find.byTooltip('Next'), findsNothing);
  });

  testWidgets('Skip finishes onboarding and remembers it', (tester) async {
    final prefs = await _preferences({});
    await _startApp(tester, prefs);
    await _passSplash(tester);

    await tester.tap(find.text('Skip'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(prefs.getBool(OnboardingRepository.seenKey), isTrue);
    expect(find.text('Welcome to Golden Maids'), findsOneWidget);
  });

  testWidgets('Get Started finishes onboarding and remembers it', (
    tester,
  ) async {
    final prefs = await _preferences({});
    await _startApp(tester, prefs);
    await _passSplash(tester);

    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Get Started'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(prefs.getBool(OnboardingRepository.seenKey), isTrue);
    expect(find.text('Welcome to Golden Maids'), findsOneWidget);
  });
}
