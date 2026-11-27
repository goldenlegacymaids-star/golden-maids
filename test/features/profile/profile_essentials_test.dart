import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_maids/core/constants/agency_contact.dart';
import 'package:golden_maids/features/authentication/domain/auth_repository.dart';
import 'package:golden_maids/features/profile/domain/account_deletion.dart';
import 'package:golden_maids/features/profile/domain/profile.dart';

import '../../helpers/fake_account_deletion_repository.dart';
import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_profile_repository.dart';
import '../../helpers/test_app.dart';

const _profileIcon = Icons.person_outline_rounded;

Finder _inDialog(String text) =>
    find.descendant(of: find.byType(AlertDialog), matching: find.text(text));

void main() {
  late FakeAuthRepository auth;
  late FakeAccountDeletionRepository deletion;
  late FakeLauncher launcher;

  setUp(() {
    auth = FakeAuthRepository(
      signedInUser: const AppUser(id: 'u1', fullName: 'Sarah Khan'),
    );
    deletion = FakeAccountDeletionRepository();
    launcher = FakeLauncher();
  });
  tearDown(() => auth.dispose());

  Future<void> openProfile(WidgetTester tester) async {
    await pumpTestApp(
      tester,
      auth: auth,
      profiles: FakeProfileRepository(
        profile: const Profile(id: 'u1', fullName: 'Sarah Khan'),
      ),
      accountDeletion: deletion,
      launcher: launcher,
    );
    await openTab(tester, _profileIcon);
  }

  testWidgets('Help Centre answers questions and contacts the agency', (
    tester,
  ) async {
    await openProfile(tester);
    await tapAndSettle(tester, find.text('Help Centre'));

    expect(find.text('Need help?'), findsOneWidget);
    await tapAndSettle(tester, find.text('Can I cancel a hiring request?'));
    expect(find.textContaining('from the Requests tab'), findsOneWidget);
    expect(find.text('When can I book?'), findsNothing);

    await tapAndSettle(tester, find.text('Call ${AgencyContact.phoneDisplay}'));
    expect(launcher.opened.single, AgencyContact.callUri());
  });

  testWidgets('Privacy Policy is shown as a draft', (tester) async {
    await openProfile(tester);
    await tapAndSettle(tester, find.text('Privacy Policy'));

    expect(find.textContaining('Draft: this text is being reviewed'), findsOneWidget);
    expect(find.text('What we collect'), findsOneWidget);
  });

  testWidgets('Terms and Conditions are shown as a draft', (tester) async {
    await openProfile(tester);
    await tapAndSettle(tester, find.text('Terms and Conditions'));

    expect(find.textContaining('Draft: this text is being reviewed'), findsOneWidget);
    await scrollTo(tester, find.text('Hiring a domestic worker'));
    expect(find.text('Hiring a domestic worker'), findsOneWidget);
    expect(find.text('Home-service bookings'), findsNothing);
  });

  group('Delete my account', () {
    testWidgets('confirm with a reason, then signed out', (tester) async {
      await openProfile(tester);

      await tapAndSettle(tester, find.text('Delete my account'));
      expect(find.text('Delete your account?'), findsOneWidget);
      await tapAndSettle(tester, find.text('Keep my account'));
      expect(deletion.requests, isEmpty);

      await tapAndSettle(tester, find.text('Delete my account'));
      await tester.enterText(find.byType(TextField), 'Moving abroad');
      await tapAndSettle(tester, _inDialog('Delete my account'));

      expect(deletion.requests, ['Moving abroad']);
      expect(auth.calls, contains('signOut'));
      expect(find.text('Welcome to Golden Maids'), findsOneWidget);
    });

    testWidgets('a pending request can be withdrawn', (tester) async {
      deletion = FakeAccountDeletionRepository(
        pending: AccountDeletionRequest(
          id: 'd1',
          createdAt: DateTime(2026, 11, 16, 12),
        ),
      );
      await openProfile(tester);

      expect(find.text('Account deletion requested'), findsOneWidget);
      expect(find.textContaining('16 November 2026'), findsOneWidget);
      expect(find.text('Delete my account'), findsNothing);

      await tapAndSettle(tester, find.text('Withdraw request'));
      expect(deletion.withdrawn, ['d1']);
      expect(find.text('Account deletion requested'), findsNothing);
      expect(find.text('Delete my account'), findsOneWidget);
      expect(auth.calls, isNot(contains('signOut')));
    });
  });
}
