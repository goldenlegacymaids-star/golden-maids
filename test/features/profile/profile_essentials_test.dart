import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_maids/core/constants/agency_contact.dart';
import 'package:golden_maids/core/widgets/app_card.dart';
import 'package:golden_maids/core/widgets/app_chip.dart';
import 'package:golden_maids/features/authentication/domain/auth_repository.dart';
import 'package:golden_maids/features/bookings/domain/booking.dart';
import 'package:golden_maids/features/profile/domain/account_deletion.dart';
import 'package:golden_maids/features/profile/domain/profile.dart';

import '../../helpers/fake_account_deletion_repository.dart';
import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_booking_repository.dart';
import '../../helpers/fake_profile_repository.dart';
import '../../helpers/test_app.dart';

const _profileIcon = Icons.person_outline_rounded;

const _home = SavedAddress(
  id: 'a1',
  label: 'Home',
  emirate: 'Dubai',
  area: 'JLT',
  building: 'Tower 2',
  apartment: '1204',
  isDefault: true,
);
const _work = SavedAddress(
  id: 'a2',
  label: 'Work',
  emirate: 'Dubai',
  area: 'Business Bay',
  building: 'Bay Square 5',
);

Finder _field(String label) => find.widgetWithText(TextFormField, label);

/// The options button on the address card labelled [label].
Finder _optionsOf(String label) => find.descendant(
  of: find.ancestor(of: find.text(label), matching: find.byType(AppCard)),
  matching: find.byTooltip('Address options'),
);

Finder _inDialog(String text) =>
    find.descendant(of: find.byType(AlertDialog), matching: find.text(text));

Future<void> _type(WidgetTester tester, String label, String text) async {
  await tester.ensureVisible(_field(label));
  await tester.enterText(_field(label), text);
  await settle(tester);
}

void main() {
  late FakeAuthRepository auth;
  late FakeBookingRepository bookings;
  late FakeAccountDeletionRepository deletion;
  late FakeLauncher launcher;

  setUp(() {
    auth = FakeAuthRepository(
      signedInUser: const AppUser(id: 'u1', fullName: 'Sarah Khan'),
    );
    bookings = FakeBookingRepository(addresses: [_work, _home]);
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
      bookings: bookings,
      accountDeletion: deletion,
      launcher: launcher,
    );
    await openTab(tester, _profileIcon);
  }

  group('Saved Addresses', () {
    testWidgets('add, make default, edit and delete', (tester) async {
      await openProfile(tester);
      await tapAndSettle(tester, find.text('Saved Addresses'));

      // The default address is listed first, with its badge.
      expect(find.text('Default'), findsOneWidget);
      expect(find.text('Apt 1204, Tower 2, JLT, Dubai'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Apt 1204, Tower 2, JLT, Dubai')).dy,
        lessThan(
          tester.getTopLeft(find.text('Bay Square 5, Business Bay, Dubai')).dy,
        ),
      );

      // Add: not the default, as one already exists.
      await tapAndSettle(tester, find.text('Add an address'));
      expect(find.text('Save address'), findsOneWidget);
      await tapAndSettle(tester, find.widgetWithText(AppChip, 'Other'));
      await _type(tester, 'Area', 'Al Barsha');
      await _type(tester, 'Building or villa', 'Villa 3');
      await tapAndSettle(tester, find.text('Save address'));
      expect(find.text('Address saved.'), findsOneWidget);
      final added = bookings.savedInputs.single;
      expect((added.label, added.area, added.building), (
        'Other',
        'Al Barsha',
        'Villa 3',
      ));
      expect(added.isDefault, isFalse);
      expect(find.textContaining('Villa 3, Al Barsha'), findsOneWidget);

      // Make Work the default.
      await tapAndSettle(tester, _optionsOf('Work'));
      await tapAndSettle(tester, find.text('Make default'));
      expect(find.text('Work is now your default.'), findsOneWidget);
      expect(
        [for (final a in bookings.addresses.where((a) => a.isDefault)) a.id],
        ['a2'],
      );

      // Edit Home: the form starts with its details.
      await tapAndSettle(tester, _optionsOf('Home'));
      await tapAndSettle(tester, find.text('Edit'));
      expect(find.text('Edit address'), findsOneWidget);
      expect(
        tester.widget<TextFormField>(_field('Area')).controller?.text,
        'JLT',
      );
      await _type(tester, 'Building or villa', 'Tower 3');
      await tapAndSettle(tester, find.text('Save changes'));
      expect(find.text('Address updated.'), findsOneWidget);
      final (id, update) = bookings.updatedAddresses.single;
      expect((id, update.building, update.apartment), ('a1', 'Tower 3', '1204'));

      // Delete Work after confirming.
      await tapAndSettle(tester, _optionsOf('Work'));
      await tapAndSettle(tester, find.text('Delete'));
      expect(find.text('Delete this address?'), findsOneWidget);
      await tapAndSettle(tester, _inDialog('Keep'));
      expect(bookings.addresses, hasLength(3));
      await tapAndSettle(tester, _optionsOf('Work'));
      await tapAndSettle(tester, find.text('Delete'));
      await tapAndSettle(tester, _inDialog('Delete'));
      expect(find.text('Address deleted.'), findsOneWidget);
      expect([for (final a in bookings.addresses) a.id], isNot(contains('a2')));
      expect(find.text('Work'), findsNothing);
    });

    testWidgets('the first address becomes the default', (tester) async {
      bookings = FakeBookingRepository();
      await openProfile(tester);
      await tapAndSettle(tester, find.text('Saved Addresses'));

      expect(find.text('No saved addresses'), findsOneWidget);
      await tapAndSettle(tester, find.text('Add an address'));
      await _type(tester, 'Area', 'JLT');
      await tapAndSettle(tester, find.text('Save address'));
      // The building is required.
      expect(find.text('Please enter the building or villa.'), findsOneWidget);
      expect(bookings.savedInputs, isEmpty);

      await _type(tester, 'Building or villa', 'Tower 1');
      await tapAndSettle(tester, find.text('Save address'));
      expect(bookings.savedInputs.single.isDefault, isTrue);
      expect(find.text('Default'), findsOneWidget);
    });
  });

  testWidgets('Help Centre answers questions and contacts the agency', (
    tester,
  ) async {
    await openProfile(tester);
    await tapAndSettle(tester, find.text('Help Centre'));

    expect(find.text('Need help?'), findsOneWidget);
    await tapAndSettle(tester, find.text('When can I book?'));
    expect(find.textContaining('8 am to 8 pm, every day'), findsOneWidget);
    await tapAndSettle(tester, find.text('Can I cancel or reschedule?'));
    expect(find.textContaining('until 24 hours before'), findsOneWidget);

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
    expect(find.text('Cancelling and rescheduling'), findsOneWidget);
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
