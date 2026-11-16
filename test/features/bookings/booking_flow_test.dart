import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_maids/core/errors/app_failure.dart';
import 'package:golden_maids/core/widgets/app_button.dart';
import 'package:golden_maids/core/widgets/app_chip.dart';
import 'package:golden_maids/features/authentication/domain/auth_repository.dart';
import 'package:golden_maids/features/bookings/domain/booking.dart';
import 'package:golden_maids/features/profile/domain/profile.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_booking_repository.dart';
import '../../helpers/fake_profile_repository.dart';
import '../../helpers/test_app.dart';

FakeProfileRepository _sarahProfile() => FakeProfileRepository(
  profile: const Profile(
    id: 'u1',
    fullName: 'Sarah Khan',
    phone: '+971501234567',
    email: 'sarah@example.com',
  ),
);

Finder _chip(String label) => find.widgetWithText(AppChip, label);

Finder _field(String label) => find.widgetWithText(TextFormField, label);

bool _continueEnabled(WidgetTester tester) =>
    tester.widget<AppButton>(find.widgetWithText(AppButton, 'Continue'))
        .onPressed !=
    null;

Future<void> _type(WidgetTester tester, String label, String text) async {
  await tester.ensureVisible(_field(label));
  await tester.enterText(_field(label), text);
  await settle(tester);
}

/// From Home: the Hourly Maid tile → details → "Book now".
Future<void> _bookHourlyMaid(WidgetTester tester) async {
  await scrollHomeTo(tester, find.text('AED 45 / hour'));
  await tapAndSettle(tester, find.text('AED 45 / hour'));
  await tapAndSettle(tester, find.text('Book now'));
}

void main() {
  late FakeAuthRepository auth;
  late FakeBookingRepository bookings;

  setUp(() {
    auth = FakeAuthRepository(
      signedInUser: const AppUser(id: 'u1', fullName: 'Sarah Khan'),
    );
    bookings = FakeBookingRepository();
  });
  tearDown(() => auth.dispose());

  Future<void> start(WidgetTester tester) => pumpTestApp(
    tester,
    auth: auth,
    profiles: _sarahProfile(),
    bookings: bookings,
  );

  testWidgets('book an hourly maid with a new address, paying by card', (
    tester,
  ) async {
    await start(tester);
    await _bookHourlyMaid(tester);

    expect(find.text('Step 1 of 3'), findsOneWidget);
    expect(find.text('2 hours'), findsOneWidget);
    expect(_continueEnabled(tester), isFalse, reason: 'no time chosen');

    await tapAndSettle(tester, find.byTooltip('More hours'));
    expect(find.text('3 hours'), findsOneWidget);
    // Slots are asked for with the chosen number of hours.
    expect(bookings.slotRequests.last.$3, 3);

    await tapAndSettle(tester, _chip('9:00 AM'));
    expect(_continueEnabled(tester), isTrue);
    await tapAndSettle(tester, find.text('Continue'));

    expect(find.text('Step 2 of 3'), findsOneWidget);
    // No saved addresses yet: the new-address form is shown.
    await _type(tester, 'Area', 'Jumeirah Lake Towers');
    await _type(tester, 'Building or villa', 'Tower 1');
    await _type(tester, 'Apartment or villa number (optional)', '1204');
    await tapAndSettle(tester, find.text('Continue'));

    expect(find.text('Step 3 of 3'), findsOneWidget);
    expect(find.text('Review your booking'), findsOneWidget);
    expect(find.text('3 hours'), findsOneWidget);
    expect(
      find.text('1204, Tower 1, Jumeirah Lake Towers, Dubai'),
      findsOneWidget,
    );
    expect(find.text('AED 135 (3 hours × AED 45)'), findsOneWidget);
    expect(find.text('Sarah Khan'), findsOneWidget);

    await tapAndSettle(tester, _chip('Card on completion'));
    await tapAndSettle(tester, find.text('Confirm booking'));

    expect(find.text('Booking received'), findsOneWidget);
    expect(find.text('Reference BK-2026-000001'), findsOneWidget);

    // The new address was saved and linked to the booking.
    expect(bookings.savedInputs.single.area, 'Jumeirah Lake Towers');
    final draft = bookings.created.single;
    final today = uaeToday();
    expect(draft.serviceId, 's3');
    expect(draft.hours, 3);
    expect(
      draft.startsAt,
      DateTime.utc(today.year, today.month, today.day, 5),
      reason: '9 am UAE is 5 am UTC',
    );
    expect(draft.addressId, 'addr-1');
    expect(draft.address.building, 'Tower 1');
    expect(draft.address.apartment, '1204');
    expect(draft.customerName, 'Sarah Khan');
    expect(draft.customerPhone, '+971501234567');
    expect(draft.paymentMethod, PaymentMethod.cardOnCompletion);

    await tapAndSettle(tester, find.text('View my bookings'));
    expect(find.text('Booking received'), findsNothing);
  });

  testWidgets('saved address, taken slots, and a slot lost while booking', (
    tester,
  ) async {
    bookings = FakeBookingRepository(
      addresses: const [
        SavedAddress(
          id: 'a1',
          label: 'Home',
          emirate: 'Dubai',
          area: 'JLT',
          building: 'Tower 2',
        ),
      ],
    )..takenHours.add(9);
    await start(tester);
    await _bookHourlyMaid(tester);

    // 9 am is taken: shown, but not as a choosable chip.
    expect(find.text('9:00 AM'), findsOneWidget);
    expect(_chip('9:00 AM'), findsNothing);

    await tapAndSettle(tester, _chip('10:00 AM'));
    await tapAndSettle(tester, find.text('Continue'));

    // The saved address is chosen; no new-address form.
    expect(find.text('Tower 2, JLT, Dubai'), findsOneWidget);
    expect(_field('Area'), findsNothing);
    await tapAndSettle(tester, find.text('Continue'));
    expect(find.text('AED 90 (2 hours × AED 45)'), findsOneWidget);

    bookings.bookingFailure = const ServerFailure(
      message: 'Sorry, this slot has just been taken. Please choose another '
          'time.',
    );
    await tapAndSettle(tester, find.text('Confirm booking'));
    expect(find.textContaining('just been taken'), findsOneWidget);
    expect(bookings.created, isEmpty);

    await tapAndSettle(tester, find.text('Choose another time'));
    expect(find.text('Step 1 of 3'), findsOneWidget);
    expect(_continueEnabled(tester), isFalse, reason: 'slot cleared');

    await tapAndSettle(tester, _chip('11:00 AM'));
    await tapAndSettle(tester, find.text('Continue'));
    await tapAndSettle(tester, find.text('Continue'));
    await tapAndSettle(tester, find.text('Confirm booking'));

    expect(find.text('Reference BK-2026-000001'), findsOneWidget);
    final draft = bookings.created.single;
    expect(draft.addressId, 'a1');
    expect(draft.address.area, 'JLT');
    expect(draft.paymentMethod, PaymentMethod.cash);
    expect(bookings.savedInputs, isEmpty, reason: 'nothing new to save');
  });

  testWidgets('a new address is not saved when unticked', (tester) async {
    await start(tester);
    await _bookHourlyMaid(tester);
    await tapAndSettle(tester, _chip('2:00 PM'));
    await tapAndSettle(tester, find.text('Continue'));

    await _type(tester, 'Area', 'Al Nahda');
    await _type(tester, 'Building or villa', 'Villa 7');
    await tapAndSettle(tester, find.text('Save this address for next time'));
    await tapAndSettle(tester, find.text('Continue'));
    await tapAndSettle(tester, find.text('Confirm booking'));

    expect(find.text('Booking received'), findsOneWidget);
    expect(bookings.savedInputs, isEmpty);
    expect(bookings.created.single.addressId, isNull);
    expect(bookings.created.single.address.area, 'Al Nahda');
  });

  testWidgets('the address and details are required', (tester) async {
    await start(tester);
    await _bookHourlyMaid(tester);
    await tapAndSettle(tester, _chip('2:00 PM'));
    await tapAndSettle(tester, find.text('Continue'));

    await tapAndSettle(tester, find.text('Continue'));
    expect(find.text('Step 2 of 3'), findsOneWidget);
    expect(find.text('Please enter the area.'), findsOneWidget);
    expect(find.text('Please enter the building or villa.'), findsOneWidget);
  });

  testWidgets('guests are asked to sign in before booking', (tester) async {
    final guest = FakeAuthRepository();
    addTearDown(guest.dispose);
    await pumpTestApp(tester, auth: guest, bookings: bookings);
    await tapAndSettle(tester, find.text('Continue as guest'));

    await _bookHourlyMaid(tester);
    expect(find.text('Sign in to book'), findsOneWidget);
    expect(find.text('Step 1 of 3'), findsNothing);
  });
}
