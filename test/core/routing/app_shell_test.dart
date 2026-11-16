import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_maids/features/authentication/domain/auth_repository.dart';
import 'package:golden_maids/features/home/presentation/home_screen.dart';
import 'package:golden_maids/features/profile/domain/profile.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_profile_repository.dart';
import '../../helpers/test_app.dart';

const _bookingsIcon = Icons.calendar_today_outlined;
const _walletIcon = Icons.account_balance_wallet_outlined;
const _profileIcon = Icons.person_outline_rounded;
const _homeIcon = Icons.home_outlined;

void main() {
  late FakeAuthRepository auth;
  late FakeProfileRepository profiles;

  FakeAuthRepository signedIn() => FakeAuthRepository(
    signedInUser: const AppUser(
      id: 'u1',
      fullName: 'Sarah Khan',
      phone: '971501234567',
    ),
  );

  setUp(() {
    auth = signedIn();
    profiles = FakeProfileRepository(
      profile: const Profile(
        id: 'u1',
        fullName: 'Sarah Khan',
        phone: '971501234567',
      ),
    );
  });
  tearDown(() => auth.dispose());

  testWidgets('the four tabs open their screens', (tester) async {
    await pumpTestApp(tester, auth: auth, profiles: profiles);
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('What services do you want to use?'), findsOneWidget);

    await openTab(tester, _bookingsIcon);
    expect(find.text('No upcoming bookings'), findsOneWidget);

    await openTab(tester, _walletIcon);
    expect(find.text('Wallet coming soon'), findsOneWidget);

    await openTab(tester, _profileIcon);
    expect(find.text('Sarah Khan'), findsOneWidget);
    expect(find.text('+971501234567'), findsOneWidget);
  });

  testWidgets('a tab keeps its state when switching away and back', (
    tester,
  ) async {
    await pumpTestApp(tester, auth: auth, profiles: profiles);
    await openTab(tester, _bookingsIcon);

    await tapAndSettle(tester, find.text('Completed'));
    expect(find.text('No completed bookings'), findsOneWidget);

    await openTab(tester, _homeIcon);
    await openTab(tester, _bookingsIcon);
    expect(find.text('No completed bookings'), findsOneWidget);
  });

  testWidgets('guests see sign-in prompts on private tabs', (tester) async {
    auth = FakeAuthRepository();
    await pumpTestApp(tester, auth: auth);
    await tapAndSettle(tester, find.text('Continue as guest'));
    expect(find.text('What services do you want to use?'), findsOneWidget);

    await openTab(tester, _bookingsIcon);
    expect(find.text('Sign in to see your bookings'), findsOneWidget);

    await openTab(tester, _walletIcon);
    expect(find.text('Sign in to use your wallet'), findsOneWidget);

    await openTab(tester, _profileIcon);
    expect(find.text('Sign in to your account'), findsOneWidget);
    expect(find.text('Help Centre'), findsOneWidget);
    expect(find.text('Log Out'), findsNothing);
  });

  testWidgets('"Coming soon" items cannot be tapped; working ones can', (
    tester,
  ) async {
    await pumpTestApp(tester, auth: auth, profiles: profiles);
    await openTab(tester, _profileIcon);

    // Visa applications, contracts, documents and payment methods are not
    // built yet.
    expect(find.text('Coming soon'), findsNWidgets(4));

    await tapAndSettle(tester, find.text('My Visa Applications'));
    expect(find.text('Sarah Khan'), findsOneWidget); // still on Profile

    await tapAndSettle(tester, find.text('My Bookings'));
    expect(find.text('No upcoming bookings'), findsOneWidget);
  });

  testWidgets('edit the profile name', (tester) async {
    await pumpTestApp(tester, auth: auth, profiles: profiles);
    await openTab(tester, _profileIcon);

    await tapAndSettle(tester, find.byTooltip('Edit profile'));
    expect(find.text('Edit profile'), findsWidgets);

    final field = find.byType(TextFormField);
    expect(tester.widget<TextFormField>(field).controller?.text, 'Sarah Khan');
    await tester.enterText(field, 'Sarah Ahmed');
    await tapAndSettle(tester, find.text('Save changes'));

    expect(profiles.profile?.fullName, 'Sarah Ahmed');
    expect(find.text('Sarah Ahmed'), findsOneWidget);
  });

  testWidgets('Android back on another tab returns to Home', (tester) async {
    await pumpTestApp(tester, auth: auth, profiles: profiles);
    await openTab(tester, _walletIcon);
    expect(find.text('Wallet coming soon'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await settle(tester);

    expect(find.text('What services do you want to use?'), findsOneWidget);
  });

  testWidgets('log out from Profile after confirming', (tester) async {
    await pumpTestApp(tester, auth: auth, profiles: profiles);
    await openTab(tester, _profileIcon);

    await tapAndSettle(tester, find.text('Log Out'));
    await tapAndSettle(tester, find.text('Cancel'));
    expect(auth.calls, isNot(contains('signOut')));

    await tapAndSettle(tester, find.text('Log Out'));
    await tapAndSettle(tester, find.text('Log out'));
    expect(auth.calls, contains('signOut'));
    expect(find.text('Welcome to Golden Maids'), findsOneWidget);
  });
}
