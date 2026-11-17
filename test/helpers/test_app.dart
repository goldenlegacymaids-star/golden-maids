import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_maids/app.dart';
import 'package:golden_maids/core/haptics/haptics.dart';
import 'package:golden_maids/core/services/external_launcher.dart';
import 'package:golden_maids/core/services/shared_preferences_provider.dart';
import 'package:golden_maids/features/authentication/data/auth_providers.dart';
import 'package:golden_maids/features/bookings/data/booking_repository.dart';
import 'package:golden_maids/features/candidates/data/candidate_repository.dart';
import 'package:golden_maids/features/documents/data/document_repository.dart';
import 'package:golden_maids/features/documents/domain/customer_document.dart';
import 'package:golden_maids/features/hiring/data/hiring_repository.dart';
import 'package:golden_maids/features/notifications/data/notification_repository.dart';
import 'package:golden_maids/features/onboarding/data/onboarding_repository.dart';
import 'package:golden_maids/features/onboarding/presentation/splash_screen.dart';
import 'package:golden_maids/features/profile/data/account_deletion_repository.dart';
import 'package:golden_maids/features/profile/data/profile_repository.dart';
import 'package:golden_maids/features/services/data/catalog_repository.dart';
import 'package:golden_maids/features/wallet/data/wallet_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_account_deletion_repository.dart';
import 'fake_auth_repository.dart';
import 'fake_booking_repository.dart';
import 'fake_candidate_repository.dart';
import 'fake_catalog_repository.dart';
import 'fake_document_repository.dart';
import 'fake_hiring_repository.dart';
import 'fake_notification_repository.dart';
import 'fake_profile_repository.dart';
import 'fake_wallet_repository.dart';

/// Starts the app as a returning user (onboarding already seen) on a
/// phone-sized screen, with fake backends, and waits past the splash.
Future<void> pumpTestApp(
  WidgetTester tester, {
  required FakeAuthRepository auth,
  FakeProfileRepository? profiles,
  FakeCatalogRepository? catalog,
  FakeCandidateRepository? candidates,
  FakeLauncher? launcher,
  FakeHiringRepository? hiring,
  FakeBookingRepository? bookings,
  FakeAccountDeletionRepository? accountDeletion,
  FakeNotificationRepository? notifications,
  FakeDocumentRepository? documents,
  FakeWalletRepository? wallet,
  Future<PickedDocument?> Function()? pickDocument,
  Map<String, Object> preferences = const {},
  /// Records the app's vibrations instead of playing them.
  List<HapticKind>? haptics,
}) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({
    OnboardingRepository.seenKey: true,
    ...preferences,
  });
  final prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      retry: (retryCount, error) => null,
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        hapticPlayerProvider.overrideWithValue((kind) async {
          haptics?.add(kind);
        }),
        authRepositoryProvider.overrideWithValue(auth),
        profileRepositoryProvider.overrideWithValue(
          profiles ?? FakeProfileRepository(),
        ),
        catalogRepositoryProvider.overrideWithValue(
          catalog ?? FakeCatalogRepository(),
        ),
        candidateRepositoryProvider.overrideWithValue(
          candidates ?? FakeCandidateRepository(),
        ),
        hiringRepositoryProvider.overrideWithValue(
          hiring ?? FakeHiringRepository(),
        ),
        accountDeletionRepositoryProvider.overrideWithValue(
          accountDeletion ?? FakeAccountDeletionRepository(),
        ),
        bookingRepositoryProvider.overrideWithValue(
          bookings ?? FakeBookingRepository(),
        ),
        notificationRepositoryProvider.overrideWithValue(
          notifications ?? FakeNotificationRepository(),
        ),
        documentRepositoryProvider.overrideWithValue(
          documents ?? FakeDocumentRepository(),
        ),
        walletRepositoryProvider.overrideWithValue(
          wallet ?? FakeWalletRepository(),
        ),
        documentPickerProvider.overrideWithValue(
          pickDocument ?? () async => null,
        ),
        externalLauncherProvider.overrideWithValue(
          (launcher ?? FakeLauncher()).call,
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

/// Whether [finder] finds something on screen (false, not an error, for
/// `.first` / `.last` finders that find nothing).
bool _onScreen(Finder finder) {
  try {
    return finder.evaluate().isNotEmpty;
  } on StateError {
    return false;
  }
}

bool _tappable(Finder finder) {
  try {
    return finder.hitTestable().evaluate().isNotEmpty;
  } on StateError {
    return false;
  }
}

/// Scrolls the screen's vertical lists, from the top down, until [finder]
/// is on screen. Long pages (Home, Profile, Help Centre) only build what is
/// near the screen.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  if (_onScreen(finder)) return;
  final lists = find.byWidgetPredicate(
    (widget) =>
        widget is Scrollable &&
        axisDirectionToAxis(widget.axisDirection) == Axis.vertical,
  );
  for (final element in lists.evaluate().toList()) {
    if (!element.mounted || element is! StatefulElement) continue;
    final state = element.state;
    if (state is! ScrollableState) continue;
    final position = state.position;
    position.jumpTo(position.minScrollExtent);
    await tester.pump();
    while (!_onScreen(finder) && position.pixels < position.maxScrollExtent) {
      position.jumpTo(math.min(position.pixels + 300, position.maxScrollExtent));
      await tester.pump();
    }
    if (_onScreen(finder)) return;
  }
}

Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
  await scrollTo(tester, finder);
  // Only scroll when needed: scrolling a row of chips to put one at its
  // start would push the earlier chips out of view.
  if (!_tappable(finder)) {
    await tester.ensureVisible(finder);
    await tester.pump();
  }
  await tester.tap(finder);
  await settle(tester);
}

/// Taps a bottom-navigation tab by its (inactive) icon.
Future<void> openTab(WidgetTester tester, IconData icon) =>
    tapAndSettle(tester, find.byIcon(icon));

/// Scrolls the Home screen until [finder] is on screen.
Future<void> scrollHomeTo(WidgetTester tester, Finder finder) async {
  await scrollTo(tester, finder);
  if (!_tappable(finder)) await tester.ensureVisible(finder);
  await settle(tester);
}

/// Records links the app tries to open in other apps.
class FakeLauncher {
  final List<Uri> opened = [];

  /// Set to false to simulate a device without the needed app.
  bool succeeds = true;

  Future<bool> call(Uri uri) async {
    opened.add(uri);
    return succeeds;
  }
}
