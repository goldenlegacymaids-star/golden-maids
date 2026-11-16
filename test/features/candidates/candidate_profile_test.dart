import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_maids/core/constants/agency_contact.dart';
import 'package:golden_maids/core/errors/app_failure.dart';
import 'package:golden_maids/core/routing/app_routes.dart';
import 'package:golden_maids/core/widgets/app_chip.dart';
import 'package:golden_maids/features/authentication/domain/auth_repository.dart';
import 'package:golden_maids/features/candidates/domain/candidate_profile.dart';
import 'package:golden_maids/features/candidates/presentation/enquiry_sheet.dart';
import 'package:golden_maids/features/home/presentation/home_screen.dart';
import 'package:golden_maids/features/profile/domain/profile.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_candidate_repository.dart';
import '../../helpers/fake_profile_repository.dart';
import '../../helpers/test_app.dart';

const _profileTab = Icons.person_outline_rounded;

/// Signed in, on Home, then opens Wanjiru's profile from Featured Maids.
Future<void> _openWanjiru(
  WidgetTester tester, {
  required FakeAuthRepository auth,
  required FakeCandidateRepository candidates,
  FakeLauncher? launcher,
  FakeProfileRepository? profiles,
}) async {
  await pumpTestApp(
    tester,
    auth: auth,
    candidates: candidates,
    launcher: launcher,
    profiles: profiles,
  );
  await tapAndSettle(tester, find.text('Wanjiru Kamau'));
  expect(find.text('Ref. GM-00001'), findsOneWidget);
}

/// Scrolls the profile until [finder] is on screen.
///
/// The profile's list is the only scrollable on screen (Home is hidden
/// under the profile page), and is found that way because rows near the
/// top go off screen as it scrolls.
Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  final list = find.byType(Scrollable).first;
  await tester.scrollUntilVisible(finder, 200, scrollable: list);
  await settle(tester);
}

void main() {
  late FakeAuthRepository auth;
  late FakeCandidateRepository candidates;
  late FakeLauncher launcher;

  setUp(() {
    auth = FakeAuthRepository(
      signedInUser: const AppUser(id: 'u1', fullName: 'Sarah Khan'),
    );
    candidates = FakeCandidateRepository();
    launcher = FakeLauncher();
  });
  tearDown(() => auth.dispose());

  group('Candidate profile', () {
    testWidgets('shows facts, details, skills, history, packages, documents', (
      tester,
    ) async {
      await _openWanjiru(tester, auth: auth, candidates: candidates);

      expect(find.text('Wanjiru Kamau'), findsWidgets);
      expect(find.text('Housemaid · 34 yrs'), findsOneWidget);
      expect(find.text('Kenya'), findsOneWidget);
      expect(find.text('6 years'), findsOneWidget);
      expect(find.text('AED 1,800'), findsOneWidget);
      expect(find.text('TEST'), findsOneWidget);

      // Scrolling puts the found row at the top, so each section is
      // reached by its first row and the rows below are then checked.
      await _scrollTo(tester, find.text('Secondary school'));
      expect(find.text('Christian'), findsOneWidget);
      expect(find.text('Single'), findsOneWidget);

      await _scrollTo(tester, find.text('English'));
      expect(find.text('Swahili'), findsOneWidget);
      expect(find.text('Fluent'), findsNWidgets(2));

      await _scrollTo(tester, find.text('Housemaid · United Arab Emirates'));
      expect(find.text('2021 – 2024'), findsOneWidget);
      expect(find.text('Housemaid · Saudi Arabia'), findsOneWidget);
      expect(find.text('2018 – 2021'), findsOneWidget);

      await _scrollTo(tester, find.text('2-Year Contract – GCC Sponsor Visa'));
      // Monthly has no price yet; the 2-Year price is Wanjiru's (Kenya).
      expect(find.text('Price on request'), findsWidgets);
      expect(find.text('AED 15,000'), findsOneWidget);

      await _scrollTo(tester, find.text('Housekeeping certificate'));
      await _scrollTo(tester, find.text('Hire this maid'));
      expect(find.text('Hire Wanjiru Kamau'), findsOneWidget);
    });

    testWidgets('a shared document opens through a short-lived link', (
      tester,
    ) async {
      await _openWanjiru(
        tester,
        auth: auth,
        candidates: candidates,
        launcher: launcher,
      );

      await _scrollTo(tester, find.text('Housekeeping certificate'));
      await tapAndSettle(tester, find.text('Housekeeping certificate'));
      expect(candidates.openedDocuments, ['k1/certificate.pdf']);
      expect(
        launcher.opened.single.toString(),
        'https://example.com/signed/k1/certificate.pdf',
      );
    });

    testWidgets('Call, WhatsApp and Email open with the candidate code', (
      tester,
    ) async {
      await _openWanjiru(
        tester,
        auth: auth,
        candidates: candidates,
        launcher: launcher,
      );

      await tapAndSettle(
        tester,
        find.byTooltip('Call ${AgencyContact.phoneDisplay}'),
      );
      expect(launcher.opened.last.toString(), 'tel:+97143234393');

      await tapAndSettle(tester, find.byTooltip('WhatsApp'));
      final whatsApp = launcher.opened.last;
      expect(whatsApp.host, 'wa.me');
      expect(whatsApp.path, '/97143234393');
      expect(
        whatsApp.queryParameters['text'],
        "Hello, I'm interested in GM-00001.",
      );

      await tapAndSettle(tester, find.byTooltip('Email'));
      final email = launcher.opened.last;
      expect(email.scheme, 'mailto');
      expect(email.path, 'info@gldws.ae');
      expect(email.queryParameters['subject'], 'Enquiry about GM-00001');
    });

    testWidgets('explains when a contact app is missing', (tester) async {
      launcher.succeeds = false;
      await _openWanjiru(
        tester,
        auth: auth,
        candidates: candidates,
        launcher: launcher,
      );

      await tapAndSettle(tester, find.byTooltip('Email'));
      expect(
        find.text('No email app found. Please write to info@gldws.ae.'),
        findsOneWidget,
      );
    });

    testWidgets('a candidate who is no longer listed shows a clear message', (
      tester,
    ) async {
      await pumpTestApp(tester, auth: auth, candidates: candidates);
      final context = tester.element(find.byType(HomeScreen));
      GoRouter.of(context).go(AppRoutes.candidate('gone'));
      await settle(tester);

      expect(
        find.text(
          'This candidate is no longer listed. Browse other available maids.',
        ),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('guests opening a profile link are sent to sign in', (
      tester,
    ) async {
      final guest = FakeAuthRepository();
      addTearDown(guest.dispose);
      await pumpTestApp(tester, auth: guest, candidates: candidates);
      await tapAndSettle(tester, find.text('Continue as guest'));

      final context = tester.element(find.byType(HomeScreen));
      GoRouter.of(context).go(AppRoutes.candidate('k1'));
      await settle(tester);

      expect(find.text('Ref. GM-00001'), findsNothing);
      expect(
        find.text('Sign in to manage your bookings and hiring requests.'),
        findsOneWidget,
      );
    });
  });

  group('Request Info', () {
    final profiles = FakeProfileRepository(
      profile: const Profile(
        id: 'u1',
        fullName: 'Sarah Khan',
        phone: '+971501234567',
        email: 'sarah@example.com',
      ),
    );

    testWidgets('sends an enquiry prefilled from the profile', (tester) async {
      await _openWanjiru(
        tester,
        auth: auth,
        candidates: candidates,
        profiles: profiles,
      );

      await tapAndSettle(tester, find.text('Request Info').last);
      expect(find.text('Sarah Khan'), findsOneWidget);
      expect(find.text('+971501234567'), findsOneWidget);

      await tapAndSettle(tester, find.widgetWithText(AppChip, 'WhatsApp'));
      await tapAndSettle(tester, find.text('Send'));

      final enquiry = candidates.enquiries.single;
      expect(enquiry.candidateId, 'k1');
      expect(enquiry.name, 'Sarah Khan');
      expect(enquiry.phone, '+971501234567');
      expect(enquiry.email, 'sarah@example.com');
      expect(enquiry.contactMethod, ContactMethod.whatsapp);
      expect(enquiry.message, contains('GM-00001'));
      expect(
        find.text("Enquiry sent (EQ-2026-000001). We'll contact you soon."),
        findsOneWidget,
      );
    });

    testWidgets('checks the form before sending', (tester) async {
      await _openWanjiru(tester, auth: auth, candidates: candidates);

      await tapAndSettle(tester, find.text('Request Info').last);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Your question'),
        '',
      );
      await tapAndSettle(tester, find.text('Send'));

      expect(find.text('Please write your question.'), findsOneWidget);
      expect(find.text('Please enter your phone number.'), findsOneWidget);
      expect(candidates.enquiries, isEmpty);
    });

    testWidgets('shows the server message and keeps the form open', (
      tester,
    ) async {
      candidates.enquiryFailure = const ValidationFailure(
        message: 'You have sent several enquiries recently.',
      );
      await _openWanjiru(
        tester,
        auth: auth,
        candidates: candidates,
        profiles: profiles,
      );

      await tapAndSettle(tester, find.text('Request Info').last);
      await tapAndSettle(tester, find.text('Send'));

      expect(
        find.text('You have sent several enquiries recently.'),
        findsOneWidget,
      );
      expect(find.text('Send'), findsOneWidget);
    });
  });

  group('Saved Maids', () {
    testWidgets('the heart saves a maid, listed in Profile → Saved Maids', (
      tester,
    ) async {
      await pumpTestApp(tester, auth: auth, candidates: candidates);

      // First featured card is Wanjiru.
      await tapAndSettle(tester, find.byTooltip('Save').first);
      expect(candidates.favouriteIds, {'k1'});

      await openTab(tester, _profileTab);
      await tapAndSettle(tester, find.text('Saved Maids'));
      expect(find.text('Wanjiru Kamau'), findsOneWidget);
      expect(find.text('Maria Santos'), findsNothing);

      await tapAndSettle(tester, find.byTooltip('Remove from saved'));
      expect(candidates.favouriteIds, isEmpty);
      expect(find.text('No saved maids yet'), findsOneWidget);
    });

    testWidgets('the heart on a profile saves and removes', (tester) async {
      await _openWanjiru(tester, auth: auth, candidates: candidates);

      await tapAndSettle(tester, find.byTooltip('Save').first);
      expect(candidates.favouriteIds, {'k1'});
      await tapAndSettle(tester, find.byTooltip('Remove from saved').first);
      expect(candidates.favouriteIds, isEmpty);
    });

    testWidgets('guests are asked to sign in to save', (tester) async {
      final guest = FakeAuthRepository();
      addTearDown(guest.dispose);
      await pumpTestApp(tester, auth: guest, candidates: candidates);
      await tapAndSettle(tester, find.text('Continue as guest'));

      await tapAndSettle(tester, find.byTooltip('Save').first);
      expect(find.text('Sign in to save maids'), findsOneWidget);
      expect(candidates.favouriteIds, isEmpty);
    });

    testWidgets('a failed save puts the heart back and explains', (
      tester,
    ) async {
      await pumpTestApp(tester, auth: auth, candidates: candidates);
      candidates.failure = const NetworkFailure();

      await tapAndSettle(tester, find.byTooltip('Save').first);
      expect(find.byTooltip('Remove from saved'), findsNothing);
      expect(find.text(const NetworkFailure().message), findsOneWidget);
    });
  });

  group('Contact and validation helpers', () {
    test('agency links', () {
      expect(AgencyContact.callUri().toString(), 'tel:+97143234393');
      expect(
        AgencyContact.emailUri('Enquiry about GM-00001').toString(),
        'mailto:info@gldws.ae?subject=Enquiry%20about%20GM-00001',
      );
      expect(
        AgencyContact.whatsAppUri('Hi there').toString(),
        'https://wa.me/97143234393?text=Hi%20there',
      );
    });

    test('enquiry phone, message and optional email rules', () {
      expect(EnquiryValidators.phone('+971 50 123 4567'), isNull);
      expect(EnquiryValidators.phone('050-1234567'), isNull);
      expect(EnquiryValidators.phone('12345'), isNotNull);
      expect(EnquiryValidators.phone('call me'), isNotNull);
      expect(EnquiryValidators.message('  '), isNotNull);
      expect(EnquiryValidators.message('x' * 1001), isNotNull);
      expect(EnquiryValidators.message('Is she available?'), isNull);
      expect(EnquiryValidators.optionalEmail(''), isNull);
      expect(EnquiryValidators.optionalEmail('not-an-email'), isNotNull);
    });
  });
}
