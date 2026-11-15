import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_maids/core/routing/app_routes.dart';
import 'package:golden_maids/features/authentication/domain/auth_repository.dart';
import 'package:golden_maids/features/home/presentation/home_screen.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/test_app.dart';

Future<void> _startApp(WidgetTester tester, FakeAuthRepository auth) =>
    pumpTestApp(tester, auth: auth);

Future<void> _settle(WidgetTester tester) => settle(tester);

Future<void> _tap(WidgetTester tester, Finder finder) =>
    tapAndSettle(tester, finder);

Future<void> _enter(WidgetTester tester, String label, String text) async {
  final field = find.widgetWithText(TextFormField, label);
  await tester.ensureVisible(field);
  await tester.enterText(field, text);
  await tester.pump();
}

void main() {
  late FakeAuthRepository auth;

  setUp(() => auth = FakeAuthRepository());
  tearDown(() => auth.dispose());

  testWidgets('guest can browse without an account', (tester) async {
    await _startApp(tester, auth);
    expect(find.text('Welcome to Golden Maids'), findsOneWidget);

    await _tap(tester, find.text('Continue as guest'));
    expect(find.text('Hello, guest'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
  });

  testWidgets('sign up with WhatsApp code', (tester) async {
    await _startApp(tester, auth);
    await _tap(tester, find.text('Create Account'));
    expect(find.text('Create your account'), findsOneWidget);

    await _enter(tester, 'Full name', 'Sarah Khan');
    await _enter(tester, 'Mobile number', '050 123 4567');
    await _tap(tester, find.text('Send code via WhatsApp'));

    expect(auth.calls, contains('sendPhoneCode:+971501234567:whatsapp'));
    expect(find.text('Enter verification code'), findsOneWidget);
    expect(find.textContaining('+971 50 ••• 4567'), findsOneWidget);

    // Entering all 6 digits verifies automatically.
    await tester.enterText(find.byType(TextFormField), FakeAuthRepository.validCode);
    await _settle(tester);

    expect(find.text('Hello, Sarah'), findsOneWidget);
  });

  testWidgets('wrong code shows an error and stays on the code screen', (
    tester,
  ) async {
    await _startApp(tester, auth);
    await _tap(tester, find.text('Create Account'));
    await _enter(tester, 'Full name', 'Sarah Khan');
    await _enter(tester, 'Mobile number', '501234567');
    await _tap(tester, find.text('Send code via WhatsApp'));

    await tester.enterText(find.byType(TextFormField), '000000');
    await _settle(tester);

    expect(find.text('This code is incorrect.'), findsOneWidget);
    expect(find.text('Enter verification code'), findsOneWidget);
  });

  testWidgets('invalid mobile number is rejected before sending', (
    tester,
  ) async {
    await _startApp(tester, auth);
    await _tap(tester, find.text('Sign In'));
    await _enter(tester, 'Mobile number', '12345');
    await _tap(tester, find.text('Send code via WhatsApp'));

    expect(
      find.text('Enter a valid United Arab Emirates mobile number'),
      findsOneWidget,
    );
    expect(auth.calls, isEmpty);
  });

  testWidgets('WhatsApp sign-in for an unknown number explains why', (
    tester,
  ) async {
    await _startApp(tester, auth);
    await _tap(tester, find.text('Sign In'));
    await _enter(tester, 'Mobile number', '501234567');
    await _tap(tester, find.text('Send code via WhatsApp'));

    expect(find.textContaining('No account found'), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
  });

  testWidgets('sign up with email, then confirm with the emailed code', (
    tester,
  ) async {
    await _startApp(tester, auth);
    await _tap(tester, find.text('Create Account'));
    await _tap(tester, find.text('Email'));

    await _enter(tester, 'Full name', 'Sarah Khan');
    await _enter(tester, 'Email address', 'sarah@example.com');
    await _enter(tester, 'Password', 'Secret123');
    await _enter(tester, 'Confirm password', 'Secret123');
    await _tap(tester, find.widgetWithText(FilledButton, 'Create Account'));

    expect(auth.calls, contains('signUpWithEmail:sarah@example.com'));
    expect(find.textContaining('sarah@example.com'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), FakeAuthRepository.validCode);
    await _settle(tester);
    expect(find.text('Hello, Sarah'), findsOneWidget);
  });

  testWidgets('weak password and mismatched confirmation are rejected', (
    tester,
  ) async {
    await _startApp(tester, auth);
    await _tap(tester, find.text('Create Account'));
    await _tap(tester, find.text('Email'));

    await _enter(tester, 'Full name', 'Sarah Khan');
    await _enter(tester, 'Email address', 'sarah@example.com');
    await _enter(tester, 'Password', 'password');
    await _enter(tester, 'Confirm password', 'different1');
    await _tap(tester, find.widgetWithText(FilledButton, 'Create Account'));

    expect(find.text('Use both letters and numbers'), findsOneWidget);
    expect(find.text('Passwords do not match'), findsOneWidget);
    expect(auth.calls, isEmpty);
  });

  testWidgets('sign in with email and password', (tester) async {
    auth.emailAccounts['sarah@example.com'] = 'Secret123';
    await _startApp(tester, auth);
    await _tap(tester, find.text('Sign In'));
    await _tap(tester, find.text('Email'));

    await _enter(tester, 'Email address', 'sarah@example.com');
    await _enter(tester, 'Password', 'wrong-password1');
    await _tap(tester, find.widgetWithText(FilledButton, 'Sign In'));
    expect(find.text('Incorrect email or password.'), findsOneWidget);

    await _enter(tester, 'Password', 'Secret123');
    await _tap(tester, find.widgetWithText(FilledButton, 'Sign In'));
    expect(find.text('Hello, Sarah'), findsOneWidget);
  });

  testWidgets('reset a forgotten password with an emailed code', (
    tester,
  ) async {
    await _startApp(tester, auth);
    await _tap(tester, find.text('Sign In'));
    await _tap(tester, find.text('Email'));
    await _tap(tester, find.text('Forgot password?'));

    await _enter(tester, 'Email address', 'sarah@example.com');
    await _tap(tester, find.text('Send reset code'));
    expect(auth.calls, contains('sendPasswordResetCode:sarah@example.com'));

    await tester.enterText(find.byType(TextFormField), FakeAuthRepository.validCode);
    await _settle(tester);
    expect(find.text('Create a new password'), findsOneWidget);

    await _enter(tester, 'New password', 'NewSecret1');
    await _enter(tester, 'Confirm new password', 'NewSecret1');
    await _tap(tester, find.text('Save password'));

    expect(auth.lastPasswordSet, 'NewSecret1');
    expect(find.text('Hello, there'), findsOneWidget);
  });

  testWidgets('signed-in user stays signed in, can log out from Profile', (tester) async {
    auth = FakeAuthRepository(
      signedInUser: const AppUser(id: 'u1', fullName: 'Sarah Khan'),
    );
    await _startApp(tester, auth);
    expect(find.text('Hello, Sarah'), findsOneWidget);

    await _tap(tester, find.byIcon(Icons.person_outline_rounded));
    await _tap(tester, find.text('Log Out'));
    await _tap(tester, find.text('Log out'));
    expect(auth.calls, contains('signOut'));
    expect(find.text('Welcome to Golden Maids'), findsOneWidget);
  });

  testWidgets('signed-in user is redirected away from sign-in screens', (
    tester,
  ) async {
    auth = FakeAuthRepository(signedInUser: const AppUser(id: 'u1'));
    await _startApp(tester, auth);

    final context = tester.element(find.byType(HomeScreen));
    GoRouter.of(context).go(AppRoutes.signIn);
    await _settle(tester);

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Welcome back'), findsNothing);
  });
}
