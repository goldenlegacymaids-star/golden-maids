import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:golden_maids/core/errors/app_failure.dart';
import 'package:golden_maids/core/routing/app_routes.dart';
import 'package:golden_maids/core/widgets/app_button.dart';
import 'package:golden_maids/core/widgets/app_chip.dart';
import 'package:golden_maids/features/authentication/domain/auth_repository.dart';
import 'package:golden_maids/features/candidates/domain/candidate.dart';
import 'package:golden_maids/features/candidates/domain/candidate_profile.dart';
import 'package:golden_maids/features/hiring/domain/hiring_request.dart';
import 'package:golden_maids/features/hiring/presentation/hire_screen.dart';
import 'package:golden_maids/features/home/presentation/home_screen.dart';
import 'package:golden_maids/features/profile/domain/profile.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_candidate_repository.dart';
import '../../helpers/fake_hiring_repository.dart';
import '../../helpers/fake_profile_repository.dart';
import '../../helpers/fake_visa_repository.dart';
import '../../helpers/test_app.dart';

const _profileTab = Icons.person_outline_rounded;

FakeProfileRepository _sarahProfile() => FakeProfileRepository(
  profile: const Profile(
    id: 'u1',
    fullName: 'Sarah Khan',
    phone: '+971501234567',
    email: 'sarah@example.com',
  ),
);

Finder _chip(String label) => find.widgetWithText(AppChip, label);

bool _continueEnabled(WidgetTester tester) =>
    tester.widget<AppButton>(find.widgetWithText(AppButton, 'Continue'))
        .onPressed !=
    null;

Future<void> _scrollTo(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await settle(tester);
}

void main() {
  late FakeAuthRepository auth;
  late FakeCandidateRepository candidates;
  late FakeHiringRepository hiring;

  setUp(() {
    auth = FakeAuthRepository(
      signedInUser: const AppUser(id: 'u1', fullName: 'Sarah Khan'),
    );
    candidates = FakeCandidateRepository();
    hiring = FakeHiringRepository();
  });
  tearDown(() => auth.dispose());

  Future<void> start(WidgetTester tester, {FakeProfileRepository? profiles}) =>
      pumpTestApp(
        tester,
        auth: auth,
        candidates: candidates,
        hiring: hiring,
        profiles: profiles ?? _sarahProfile(),
      );

  /// From Home: Wanjiru's profile → "Hire Wanjiru Kamau".
  Future<void> hireWanjiru(WidgetTester tester) async {
    await tapAndSettle(tester, find.text('Wanjiru Kamau'));
    await _scrollTo(tester, find.text('Hire Wanjiru Kamau'));
    await tapAndSettle(tester, find.text('Hire Wanjiru Kamau'));
    expect(find.text('Step 1 of 3'), findsOneWidget);
  }

  /// From Home: See All → Find a Maid → "Hire a Maid".
  Future<void> hireFromDirectory(WidgetTester tester) async {
    await tapAndSettle(tester, find.text('See All'));
    await tapAndSettle(tester, find.text('Hire a Maid'));
    expect(find.text('Step 1 of 4'), findsOneWidget);
  }

  group('Hiring from a maid profile', () {
    testWidgets('company visa, monthly: choose months, review and submit', (
      tester,
    ) async {
      await start(tester);
      await hireWanjiru(tester);

      expect(_continueEnabled(tester), isFalse);
      await tapAndSettle(tester, find.text('Company visa'));
      // The only company package for Wanjiru is chosen automatically.
      expect(find.text('Full-Time Live-In Maid – Monthly'), findsOneWidget);
      expect(find.text('Price on request'), findsOneWidget);
      expect(_continueEnabled(tester), isFalse, reason: 'months not chosen');

      await tapAndSettle(tester, find.byTooltip('More months'));
      await tapAndSettle(tester, find.byTooltip('More months'));
      expect(find.text('2 months'), findsOneWidget);

      await tapAndSettle(tester, find.text('Continue'));
      expect(find.text('Step 2 of 3'), findsOneWidget);
      expect(find.text('Sarah Khan'), findsOneWidget);

      await tapAndSettle(tester, find.text('Continue'));
      expect(find.text('Step 3 of 3'), findsOneWidget);
      expect(find.text('Review your request'), findsOneWidget);
      expect(find.text('2 months'), findsOneWidget);
      expect(find.text('Wanjiru Kamau'), findsWidgets);

      await tapAndSettle(tester, find.text('Submit request'));
      expect(find.text('Request submitted'), findsOneWidget);
      expect(find.text('Reference HR-2026-000001'), findsOneWidget);

      final draft = hiring.submitted.single;
      expect(draft.packageId, 'pkg-monthly');
      expect(draft.durationMonths, 2);
      expect(draft.candidateId, 'k1');
      expect(draft.sponsorNationality, isNull);
      expect(draft.name, 'Sarah Khan');
      expect(draft.phone, '+971501234567');
      expect(draft.emirate, 'Dubai');

      await tapAndSettle(tester, find.text('View my requests'));
      expect(find.text('Requests'), findsWidgets);
      expect(find.text('HR-2026-000001'), findsOneWidget);
      expect(find.text('Submitted'), findsOneWidget);
    });

    testWidgets('a maid who is not available cannot be hired', (tester) async {
      await start(tester);
      final context = tester.element(find.byType(HomeScreen));
      GoRouter.of(context).go(AppRoutes.hire(candidateId: 'm1'));
      await settle(tester);

      expect(find.text('Thandar Aung is not available right now'), findsOneWidget);
      expect(find.text('Step 1 of 3'), findsNothing);
    });
  });

  group('Hiring from Find a Maid', () {
    testWidgets('GCC sponsor visa: nationality required, then pick a maid', (
      tester,
    ) async {
      await start(tester);
      await hireFromDirectory(tester);

      await tapAndSettle(tester, find.text('GCC sponsor visa'));
      expect(find.text('24 months (fixed)'), findsOneWidget);
      expect(_continueEnabled(tester), isFalse, reason: 'nationality needed');

      // Priced by nationality: the lowest price until a maid is chosen.
      expect(find.text('From AED 15,000'), findsOneWidget);
      await tapAndSettle(tester, _chip('Saudi Arabia'));
      await tapAndSettle(tester, find.text('Continue'));
      expect(find.text('Step 2 of 4'), findsOneWidget);
      // Each maid shows the price for her nationality.
      expect(find.textContaining('Philippines · AED 16,500'), findsOneWidget);
      expect(find.textContaining('Kenya · AED 15,000'), findsOneWidget);

      // Only available maids offering the GCC package are listed.
      expect(find.text('Wanjiru Kamau'), findsOneWidget);
      expect(find.text('Maria Santos'), findsOneWidget);
      expect(find.text('Thandar Aung'), findsNothing);
      expect(_continueEnabled(tester), isFalse, reason: 'no maid chosen');

      await tapAndSettle(tester, find.text('Maria Santos'));
      await tapAndSettle(tester, find.text('Continue'));
      await tapAndSettle(tester, find.text('Continue'));
      expect(find.text('Step 4 of 4'), findsOneWidget);
      expect(find.text('Saudi Arabia'), findsOneWidget);
      expect(find.text('24 months'), findsOneWidget);
      expect(find.text('Philippines'), findsOneWidget);
      expect(find.text('AED 16,500'), findsOneWidget);

      await tapAndSettle(tester, find.text('Submit request'));
      final draft = hiring.submitted.single;
      expect(draft.packageId, 'pkg-gcc');
      expect(draft.durationMonths, 24);
      expect(draft.sponsorNationality, 'SA');
      expect(draft.candidateId, 'p1');
      // The database fills in a chosen maid's nationality.
      expect(draft.preferredNationality, isNull);
    });

    testWidgets('GCC sponsor visa with a recommended maid: choose nationality', (
      tester,
    ) async {
      await start(tester);
      await hireFromDirectory(tester);

      await tapAndSettle(tester, find.text('GCC sponsor visa'));
      await tapAndSettle(tester, _chip('United Arab Emirates'));
      await tapAndSettle(tester, find.text('Continue'));
      await tapAndSettle(tester, find.text('Let the agency recommend someone'));

      // Where she should be, and her nationality (the price depends on
      // it), must both be chosen.
      expect(find.text('Where should she be?'), findsOneWidget);
      expect(find.text("Maid's nationality"), findsOneWidget);
      expect(_continueEnabled(tester), isFalse, reason: 'location needed');
      await tapAndSettle(tester, find.text('Outside the UAE'));
      expect(_continueEnabled(tester), isFalse, reason: 'nationality needed');
      await scrollTo(tester, find.text('Madagascar'));
      expect(find.text('Price on request'), findsWidgets);
      await tapAndSettle(tester, find.text('Kenya'));
      expect(_continueEnabled(tester), isTrue);

      await tapAndSettle(tester, find.text('Continue'));
      await tapAndSettle(tester, find.text('Continue'));
      expect(find.text('Agency recommendation'), findsOneWidget);
      expect(find.text('Kenya'), findsOneWidget);
      expect(find.text('Outside the UAE'), findsOneWidget);
      expect(find.text('10–20 days after confirmation'), findsOneWidget);
      expect(find.text('AED 15,000'), findsOneWidget);

      await tapAndSettle(tester, find.text('Submit request'));
      final draft = hiring.submitted.single;
      expect(draft.candidateId, isNull);
      expect(draft.preferredNationality, 'Kenya');
      expect(draft.maidLocation, MaidLocation.outsideUae);
    });

    testWidgets('the agency can be asked to recommend a maid', (tester) async {
      await start(tester);
      await hireFromDirectory(tester);

      await tapAndSettle(tester, find.text('Company visa'));
      await tapAndSettle(tester, find.byTooltip('More months'));
      await tapAndSettle(tester, find.text('Continue'));
      await tapAndSettle(tester, find.text('Let the agency recommend someone'));
      await tapAndSettle(tester, find.text('In the UAE'));
      await tapAndSettle(tester, find.text('Continue'));
      await tapAndSettle(tester, find.text('Continue'));

      expect(find.text('Agency recommendation'), findsOneWidget);
      expect(find.text('In the UAE'), findsOneWidget);
      await tapAndSettle(tester, find.text('Submit request'));
      final draft = hiring.submitted.single;
      expect(draft.candidateId, isNull);
      expect(draft.durationMonths, 1);
      expect(draft.maidLocation, MaidLocation.inUae);
    });

    testWidgets('guests are asked to sign in', (tester) async {
      final guest = FakeAuthRepository();
      addTearDown(guest.dispose);
      await pumpTestApp(tester, auth: guest, candidates: candidates);
      await tapAndSettle(tester, find.text('Continue as guest'));
      await tapAndSettle(tester, find.text('See All'));

      await tapAndSettle(tester, find.text('Hire a Maid'));
      expect(find.text('Sign in to hire a maid'), findsOneWidget);
    });
  });

  group('Hiring form checks', () {
    testWidgets('details are validated before the review', (tester) async {
      await start(tester, profiles: FakeProfileRepository());
      await hireWanjiru(tester);
      await tapAndSettle(tester, find.text('Company visa'));
      await tapAndSettle(tester, find.byTooltip('More months'));
      await tapAndSettle(tester, find.text('Continue'));

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Number of people (optional)'),
        '40',
      );
      await tapAndSettle(tester, find.text('Continue'));

      expect(find.text('Step 2 of 3'), findsOneWidget);
      expect(find.text('Please enter your phone number.'), findsOneWidget);
      expect(find.text('Please enter a number from 1 to 30.'), findsOneWidget);
    });

    testWidgets('a refused request shows the reason and stays on review', (
      tester,
    ) async {
      hiring.failure = const ValidationFailure(
        message: 'This worker is no longer available.',
      );
      await start(tester);
      await hireWanjiru(tester);
      await tapAndSettle(tester, find.text('Company visa'));
      await tapAndSettle(tester, find.byTooltip('More months'));
      await tapAndSettle(tester, find.text('Continue'));
      await tapAndSettle(tester, find.text('Continue'));
      await tapAndSettle(tester, find.text('Submit request'));

      await _scrollTo(tester, find.text('This worker is no longer available.'));
      expect(find.text('Step 3 of 3'), findsOneWidget);
      expect(find.text('Request submitted'), findsNothing);
    });
  });

  group('My Hiring Requests', () {
    setUp(() {
      hiring = FakeHiringRepository(
        requests: [
          FakeHiringRepository.sample(id: 'r1', reference: 'HR-2026-000010'),
          FakeHiringRepository.sample(
            id: 'r2',
            reference: 'HR-2026-000011',
            status: HiringStatus.shortlisted,
            candidateId: null,
          ),
        ],
      );
      hiring.history['r1'] = [
        HiringStatusEvent(
          status: HiringStatus.submitted,
          createdAt: DateTime(2026, 11, 10, 9, 30),
        ),
      ];
      hiring.history['r2'] = [
        HiringStatusEvent(
          status: HiringStatus.submitted,
          createdAt: DateTime(2026, 11, 10, 9, 30),
        ),
        HiringStatusEvent(
          status: HiringStatus.shortlisted,
          note: 'Two maids shortlisted for you.',
          createdAt: DateTime(2026, 11, 12, 14),
        ),
      ];
    });

    Future<void> openRequests(WidgetTester tester) async {
      await start(tester);
      await openTab(tester, _profileTab);
      await tapAndSettle(tester, find.text('My Hiring Requests'));
    }

    testWidgets('lists requests with their status', (tester) async {
      await openRequests(tester);

      expect(find.text('HR-2026-000010'), findsOneWidget);
      expect(find.text('HR-2026-000011'), findsOneWidget);
      expect(find.text('Submitted'), findsOneWidget);
      expect(find.text('Shortlisted'), findsOneWidget);
      expect(find.text('Agency recommendation'), findsOneWidget);
      expect(find.text('Wanjiru Kamau'), findsOneWidget);
    });

    testWidgets('details show the timeline; shortlisted cannot be cancelled', (
      tester,
    ) async {
      await openRequests(tester);
      await tapAndSettle(tester, find.text('HR-2026-000011'));

      expect(find.text('Progress'), findsOneWidget);
      expect(find.text('Two maids shortlisted for you.'), findsOneWidget);
      expect(find.text('Cancel request'), findsNothing);
    });

    testWidgets('a submitted request can be cancelled after confirming', (
      tester,
    ) async {
      await openRequests(tester);
      await tapAndSettle(tester, find.text('HR-2026-000010'));

      await tapAndSettle(tester, find.text('Cancel request'));
      expect(find.text('Cancel this request?'), findsOneWidget);
      await tapAndSettle(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Cancel request'),
        ),
      );

      expect(hiring.requests.first.status, HiringStatus.cancelled);
      expect(find.text('Request cancelled.'), findsOneWidget);
      expect(find.text('Cancelled'), findsWidgets);
      expect(find.text('Cancel request'), findsNothing);
    });

    testWidgets('an empty list explains how to start', (tester) async {
      hiring = FakeHiringRepository();
      await openRequests(tester);
      expect(find.text('No hiring requests yet'), findsOneWidget);
    });

    testWidgets('the Requests tab links a request to its visa progress', (
      tester,
    ) async {
      hiring = FakeHiringRepository(
        requests: [
          FakeHiringRepository.sample(id: 'r-v1', reference: 'HR-2026-000004'),
        ],
      );
      await pumpTestApp(
        tester,
        auth: auth,
        candidates: candidates,
        hiring: hiring,
        profiles: _sarahProfile(),
        visas: FakeVisaRepository(
          applications: [FakeVisaRepository.abroad()],
        ),
      );
      await openTab(tester, Icons.assignment_outlined);
      expect(find.text('HR-2026-000004'), findsOneWidget);

      await tapAndSettle(tester, find.text('Visa progress'));
      expect(find.text('Ref. HR-2026-000004'), findsOneWidget);
    });
  });

  group('Hiring rules', () {
    const monthly = RecruitmentPackage(
      id: 'm',
      slug: 'live-in-monthly',
      name: 'Monthly',
      visaType: 'company',
      contractTerm: 'monthly',
      minMonths: 1,
      maxMonths: 11,
    );
    const yearly = RecruitmentPackage(
      id: 'y',
      slug: 'live-in-yearly',
      name: 'Yearly',
      visaType: 'company',
      contractTerm: 'yearly',
      minMonths: 12,
      maxMonths: 24,
      monthStep: 12,
    );

    test('duration options follow the package', () {
      expect(durationOptions(monthly), List.generate(11, (i) => i + 1));
      expect(durationOptions(yearly), [12, 24]);
      expect(
        durationOptions(FakeCandidateRepository.defaultPackages.last),
        [24],
      );
    });

    test('only submitted / under review requests can be cancelled', () {
      expect(HiringStatus.submitted.canCancel, isTrue);
      expect(HiringStatus.underReview.canCancel, isTrue);
      expect(HiringStatus.shortlisted.canCancel, isFalse);
      expect(HiringStatus.fromValue('visa_processing').label, 'Visa processing');
    });

    test('a draft becomes the insert row the database expects', () {
      final json = HiringDraft(
        packageId: 'p',
        durationMonths: 12,
        name: 'Sarah Khan',
        phone: '+971501234567',
        emirate: 'Sharjah',
        sponsorNationality: 'AE',
        preferredStartDate: DateTime(2027, 1, 5),
        contactMethod: ContactMethod.whatsapp,
      ).toInsertJson();
      expect(json['preferred_start_date'], '2027-01-05');
      expect(json['sponsor_nationality'], 'AE');
      expect(json['contact_method'], 'whatsapp');
      expect(json.containsKey('customer_id'), isFalse);
      expect(json.containsKey('status'), isFalse);
    });

    test('reads a request with its package and candidate', () {
      final request = HiringRequest.fromJson({
        'id': 'r',
        'reference': 'HR-2026-000001',
        'package_id': 'p',
        'duration_months': 24,
        'sponsor_nationality': 'QA',
        'candidate_id': null,
        'status': 'under_review',
        'created_at': '2026-11-16T07:00:00+00:00',
        'customer_name': 'Sarah Khan',
        'customer_phone': '+971501234567',
        'customer_email': null,
        'emirate': 'Dubai',
        'household_size': 4,
        'has_children': true,
        'has_elderly': false,
        'has_pets': false,
        'preferred_start_date': '2026-12-01',
        'requirements': '',
        'contact_method': 'email',
        'recruitment_packages': {'name': '2-Year Contract'},
        'candidates': null,
      });
      expect(request.packageName, '2-Year Contract');
      expect(request.maidLabel, 'Agency recommendation');
      expect(request.status, HiringStatus.underReview);
      expect(request.contactMethod, ContactMethod.email);
      expect(request.preferredStartDate, DateTime(2026, 12));
    });

    test('household size and requirements limits', () {
      expect(HiringValidators.householdSize(''), isNull);
      expect(HiringValidators.householdSize('4'), isNull);
      expect(HiringValidators.householdSize('0'), isNotNull);
      expect(HiringValidators.householdSize('31'), isNotNull);
      expect(HiringValidators.requirements('x' * 2001), isNotNull);
    });
  });
}
