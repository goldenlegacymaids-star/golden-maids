import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_maids/app.dart';
import 'package:golden_maids/core/services/shared_preferences_provider.dart';
import 'package:golden_maids/features/authentication/data/auth_providers.dart';
import 'package:golden_maids/features/onboarding/data/onboarding_repository.dart';
import 'package:golden_maids/features/onboarding/presentation/splash_screen.dart';
import 'package:golden_maids/features/profile/data/profile_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_auth_repository.dart';
import 'fake_profile_repository.dart';

/// Starts the app as a returning user (onboarding already seen) on a
/// phone-sized screen, with fake backends, and waits past the splash.
Future<void> pumpTestApp(
  WidgetTester tester, {
  required FakeAuthRepository auth,
  FakeProfileRepository? profiles,
}) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({OnboardingRepository.seenKey: true});
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        authRepositoryProvider.overrideWithValue(auth),
        profileRepositoryProvider.overrideWithValue(
          profiles ?? FakeProfileRepository(),
        ),
      ],
      child: const GoldenMaidsApp(),
    ),
  );
  await tester.pump(SplashScreen.displayTime);
  await settle(tester);
}

/// Pumps long enough for async work and page transitions to finish.
/// (Some screens run timers, so pumpAndSettle is avoided.)
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await settle(tester);
}

/// Taps a bottom-navigation tab by its (inactive) icon.
Future<void> openTab(WidgetTester tester, IconData icon) =>
    tapAndSettle(tester, find.byIcon(icon));
