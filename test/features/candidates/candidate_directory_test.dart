import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_maids/core/errors/app_failure.dart';
import 'package:golden_maids/core/widgets/app_chip.dart';
import 'package:golden_maids/features/authentication/domain/auth_repository.dart';
import 'package:golden_maids/features/candidates/domain/candidate.dart';
import 'package:golden_maids/features/candidates/presentation/candidate_directory_screen.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_candidate_repository.dart';
import '../../helpers/test_app.dart';

Finder _chip(String label) => find.widgetWithText(AppChip, label);

/// Inside the open bottom sheet.
Finder _inSheet(String text) =>
    find.descendant(of: find.byType(BottomSheet), matching: find.text(text));

/// Picks one nationality ("All" clears them) in the Nationality sheet.
Future<void> _tapNationality(WidgetTester tester, String label) async {
  await tapAndSettle(
    tester,
    find.byKey(CandidateDirectoryScreen.nationalityChipKey),
  );
  final target = _inSheet(label == 'All' ? 'All nationalities' : label);
  await tester.ensureVisible(target);
  await tapAndSettle(tester, target);
  await tapAndSettle(tester, _inSheet('Show results'));
}

/// Chooses an option in the Location or Visa sheet.
Future<void> _choose(WidgetTester tester, Key chip, String option) async {
  await tapAndSettle(tester, find.byKey(chip));
  await tapAndSettle(tester, _inSheet(option));
}

/// Opens "Find a Maid" from the Featured Maids "See All" link.
Future<void> _openDirectory(WidgetTester tester) async {
  await tapAndSettle(tester, find.text('See All'));
  expect(find.text('Find a Maid'), findsOneWidget);
}

void main() {
  late FakeAuthRepository auth;
  late FakeCandidateRepository candidates;

  setUp(() {
    auth = FakeAuthRepository(
      signedInUser: const AppUser(id: 'u1', fullName: 'Sarah Khan'),
    );
    candidates = FakeCandidateRepository();
  });
  tearDown(() => auth.dispose());

  group('Featured Maids on Home', () {
    testWidgets('shows featured candidates with their TEST label', (
      tester,
    ) async {
      await pumpTestApp(tester, auth: auth, candidates: candidates);

      expect(find.text('Featured Maids'), findsOneWidget);
      expect(find.text('Wanjiru Kamau'), findsOneWidget);
      expect(find.text('Housemaid · 34 yrs'), findsOneWidget);
      expect(find.text('AED 1,800 / month'), findsOneWidget);
      expect(find.text('TEST'), findsWidgets);
      // GM-00004 is not featured.
      expect(find.text('GM-00004'), findsNothing);
    });

    testWidgets('is hidden when there are no featured candidates', (
      tester,
    ) async {
      candidates = FakeCandidateRepository(
        candidates: FakeCandidateRepository.defaultCandidates
            .where((c) => !c.isFeatured)
            .toList(),
      );
      await pumpTestApp(tester, auth: auth, candidates: candidates);

      expect(find.text('Featured Maids'), findsNothing);
      expect(find.text('Categories'), findsOneWidget);
    });
  });

  group('Find a Maid', () {
    testWidgets('lists candidates; a hidden name shows the code', (
      tester,
    ) async {
      await pumpTestApp(tester, auth: auth, candidates: candidates);
      await _openDirectory(tester);

      expect(find.text('4 candidates'), findsOneWidget);
      expect(find.text('Wanjiru Kamau'), findsOneWidget);
      expect(find.text('Thandar Aung'), findsOneWidget);
      expect(find.text('Maria Santos'), findsOneWidget);
      expect(find.text('GM-00004'), findsOneWidget);
      expect(find.text('Reserved'), findsOneWidget);
      expect(find.text('9 yrs experience'), findsOneWidget);
    });

    testWidgets('nationality chips filter the list', (tester) async {
      await pumpTestApp(tester, auth: auth, candidates: candidates);
      await _openDirectory(tester);

      await _tapNationality(tester, 'Kenya');
      expect(find.text('1 candidate'), findsOneWidget);
      expect(find.text('Wanjiru Kamau'), findsOneWidget);
      expect(find.text('Maria Santos'), findsNothing);

      // The chip shows the choice.
      expect(
        find.descendant(
          of: find.byKey(CandidateDirectoryScreen.nationalityChipKey),
          matching: find.text('Kenya'),
        ),
        findsOneWidget,
      );

      await _tapNationality(tester, 'Philippines');
      expect(find.text('2 candidates'), findsOneWidget);
      expect(find.text('Kenya +1'), findsOneWidget);

      await _tapNationality(tester, 'All');
      expect(find.text('4 candidates'), findsOneWidget);
      expect(candidates.searches.last.nationalities, isEmpty);
    });

    testWidgets('Home opens a visa route; the In / Outside the UAE switch '
        'filters', (tester) async {
      await pumpTestApp(tester, auth: auth, candidates: candidates);

      expect(find.text('Hire a Maid'), findsOneWidget);
      await tapAndSettle(tester, find.text('Company Visa'));
      expect(find.text('Find a Maid'), findsOneWidget);
      expect(candidates.searches.last.visa, VisaRoute.company);
      expect(find.text('4 candidates'), findsOneWidget);
      expect(find.text('In the UAE · Available now'), findsWidgets);

      await _choose(
        tester,
        CandidateDirectoryScreen.locationChipKey,
        'Outside the UAE',
      );
      expect(find.text('1 candidate'), findsOneWidget);
      expect(find.text('Thandar Aung'), findsOneWidget);
      expect(
        find.text('Outside the UAE · Arrival on request'),
        findsOneWidget,
      );
      expect(candidates.searches.last.location, MaidLocation.outsideUae);

      await _choose(
        tester,
        CandidateDirectoryScreen.visaChipKey,
        'GCC Sponsor Visa',
      );
      expect(find.text('No candidates found'), findsOneWidget);

      await _choose(
        tester,
        CandidateDirectoryScreen.locationChipKey,
        'In the UAE',
      );
      expect(find.text('2 candidates'), findsOneWidget);
      expect(find.text('Thandar Aung'), findsNothing);
    });

    testWidgets('an empty result explains what to do', (tester) async {
      await pumpTestApp(tester, auth: auth, candidates: candidates);
      await _openDirectory(tester);

      await _tapNationality(tester, 'Indonesia');
      expect(find.text('No candidates found'), findsOneWidget);
    });

    testWidgets('search finds a candidate by code', (tester) async {
      await pumpTestApp(tester, auth: auth, candidates: candidates);
      await _openDirectory(tester);

      await tester.enterText(find.byType(TextField), 'gm-00004');
      await settle(tester);
      expect(find.text('1 candidate'), findsOneWidget);
      expect(find.text('GM-00004'), findsOneWidget);
      expect(find.text('Wanjiru Kamau'), findsNothing);
    });

    testWidgets('the filter sheet filters by skill and can be cleared', (
      tester,
    ) async {
      await pumpTestApp(tester, auth: auth, candidates: candidates);
      await _openDirectory(tester);

      await tapAndSettle(tester, find.byTooltip('Filters'));
      expect(find.text('Job type'), findsOneWidget);
      expect(find.text('Package'), findsOneWidget);
      await tapAndSettle(tester, _chip('Childcare'));
      await tapAndSettle(tester, find.text('Show results'));

      expect(find.text('1 candidate'), findsOneWidget);
      expect(find.text('Thandar Aung'), findsOneWidget);
      expect(candidates.searches.last.skills, {CandidateSkill.childcare});

      await tapAndSettle(tester, find.text('Clear filters (1)'));
      expect(find.text('4 candidates'), findsOneWidget);
    });

    testWidgets('package and availability filters combine', (tester) async {
      await pumpTestApp(tester, auth: auth, candidates: candidates);
      await _openDirectory(tester);

      await tapAndSettle(tester, find.byTooltip('Filters'));
      await tapAndSettle(tester, _chip('2-Year GCC'));
      await tapAndSettle(tester, find.text('Show results'));
      expect(find.text('2 candidates'), findsOneWidget);
      expect(find.text('Thandar Aung'), findsNothing);

      await tapAndSettle(tester, find.byTooltip('Filters'));
      await tapAndSettle(tester, find.text('Available now only'));
      await tapAndSettle(tester, find.text('Show results'));
      expect(find.text('2 candidates'), findsOneWidget);
      expect(candidates.searches.last.packageId, 'pkg-gcc');
      expect(candidates.searches.last.availableOnly, isTrue);
    });

    testWidgets('sorting by experience puts the most experienced first', (
      tester,
    ) async {
      await pumpTestApp(tester, auth: auth, candidates: candidates);
      await _openDirectory(tester);

      await tapAndSettle(tester, find.byTooltip('Sort'));
      await tapAndSettle(tester, find.text('Most experienced').last);

      final maria = tester.getTopLeft(find.text('Maria Santos')).dy;
      final wanjiru = tester.getTopLeft(find.text('Wanjiru Kamau')).dy;
      expect(maria, lessThan(wanjiru));
    });

    testWidgets('the filter row slides away when scrolling down and comes '
        'back when scrolling up', (tester) async {
      candidates = FakeCandidateRepository(
        candidates: [
          for (var i = 1; i <= 12; i++)
            Candidate(
              id: 'c$i',
              code: 'GM-${(100 + i).toString().padLeft(5, '0')}',
              displayName: 'Maid $i',
              nationality: 'Kenya',
              age: 30,
              yearsExperience: 3,
              // Featured, so Home shows "See All".
              isFeatured: true,
            ),
        ],
      );
      await pumpTestApp(tester, auth: auth, candidates: candidates);
      await _openDirectory(tester);

      // The bar's height shrinks to 0 when it slides away.
      double barHeight() => tester
          .getSize(find.byKey(CandidateDirectoryScreen.filterBarKey))
          .height;
      expect(barHeight(), greaterThan(40));

      await tester.drag(find.text('Maid 3'), const Offset(0, -300));
      await settle(tester);
      expect(barHeight(), 0);

      await tester.drag(find.text('Maid 4'), const Offset(0, 120));
      await settle(tester);
      expect(barHeight(), greaterThan(40));
    });

    testWidgets('loading errors show a retry that recovers', (tester) async {
      await pumpTestApp(tester, auth: auth, candidates: candidates);
      candidates.failure = const NetworkFailure();
      await _openDirectory(tester);

      expect(find.text('Try again'), findsOneWidget);
      candidates.failure = null;
      await tapAndSettle(tester, find.text('Try again'));
      expect(find.text('4 candidates'), findsOneWidget);
    });
  });

  group('Opening a candidate', () {
    testWidgets('guests are asked to sign in', (tester) async {
      final guest = FakeAuthRepository();
      addTearDown(guest.dispose);
      await pumpTestApp(tester, auth: guest, candidates: candidates);
      // Guests start on the welcome screen.
      await tapAndSettle(tester, find.text('Continue as guest'));

      await tapAndSettle(tester, find.text('Wanjiru Kamau'));
      expect(find.text('Sign in to view Wanjiru Kamau'), findsOneWidget);

      await tapAndSettle(
        tester,
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Sign In'),
        ),
      );
      expect(find.text('Sign in to view Wanjiru Kamau'), findsNothing);
      expect(
        find.text('Sign in to manage your bookings and hiring requests.'),
        findsOneWidget,
      );
    });

    testWidgets('signed-in users open the full profile', (tester) async {
      await pumpTestApp(tester, auth: auth, candidates: candidates);
      await _openDirectory(tester);

      await tapAndSettle(tester, find.text('Maria Santos'));
      expect(find.text('Ref. GM-00003'), findsOneWidget);
      expect(find.text('Request Info'), findsOneWidget);
    });
  });

  group('CandidateFilter', () {
    test('equal filters are equal regardless of set order', () {
      const a = CandidateFilter(
        nationalities: {'Kenya', 'Myanmar'},
        skills: {CandidateSkill.cooking, CandidateSkill.cleaning},
      );
      const b = CandidateFilter(
        nationalities: {'Myanmar', 'Kenya'},
        skills: {CandidateSkill.cleaning, CandidateSkill.cooking},
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == a.copyWith(availableOnly: true), isFalse);
    });

    test('counts active filters and clears them, keeping search and sort', () {
      final filter = const CandidateFilter(
        query: 'maria',
        sort: CandidateSort.mostExperienced,
      ).copyWith(
        nationalities: {'Kenya'},
        designation: () => 'Nanny',
        packageId: () => 'pkg',
        skills: {CandidateSkill.cooking},
        availableOnly: true,
      );
      expect(filter.activeCount, 5);

      final cleared = filter.cleared();
      expect(cleared.activeCount, 0);
      expect(cleared.query, 'maria');
      expect(cleared.sort, CandidateSort.mostExperienced);
      expect(filter.copyWith(designation: () => null).designation, isNull);
    });
  });

  group('Candidate', () {
    test('reads card columns and shows the code when the name is hidden', () {
      final candidate = Candidate.fromJson({
        'id': 'x',
        'code': 'GM-00010',
        'display_name': null,
        'nationality': 'Indonesia',
        'age': 29,
        'designation': 'Cook',
        'years_experience': 3,
        'expected_salary': 1500,
        'availability_status': 'reserved',
        'available_from': '2026-12-01',
        'is_featured': false,
        'is_test': false,
      });
      expect(candidate.title, 'GM-00010');
      expect(candidate.expectedSalary, 1500.0);
      expect(candidate.availability, CandidateAvailability.reserved);
      expect(candidate.availableFrom, DateTime(2026, 12));
    });
  });
}
