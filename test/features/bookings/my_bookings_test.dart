import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_maids/core/constants/agency_contact.dart';
import 'package:golden_maids/core/widgets/app_button.dart';
import 'package:golden_maids/core/widgets/app_chip.dart';
import 'package:golden_maids/features/authentication/domain/auth_repository.dart';
import 'package:golden_maids/features/bookings/domain/booking.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_booking_repository.dart';
import '../../helpers/test_app.dart';

const _bookingsIcon = Icons.calendar_today_outlined;

Finder _chip(String label) => find.widgetWithText(AppChip, label);

bool _enabled(WidgetTester tester, String label) =>
    tester.widget<AppButton>(find.widgetWithText(AppButton, label)).onPressed !=
    null;

void main() {
  late FakeAuthRepository auth;
  late FakeBookingRepository bookings;
  late FakeLauncher launcher;

  final upcoming = FakeBookingRepository.sample(
    id: 'b1',
    reference: 'BK-2026-000010',
  );
  final active = FakeBookingRepository.sample(
    id: 'b2',
    reference: 'BK-2026-000011',
    status: BookingStatus.inProgress,
    startsIn: const Duration(hours: -1),
    serviceName: 'Home Cleaning',
    staffName: 'Grace K.',
    staffYears: 5,
  );
  final completed = FakeBookingRepository.sample(
    id: 'b3',
    reference: 'BK-2026-000012',
    status: BookingStatus.completed,
    startsIn: const Duration(days: -5),
  );
  final cancelled = FakeBookingRepository.sample(
    id: 'b4',
    reference: 'BK-2026-000013',
    status: BookingStatus.cancelled,
    cancelReason: 'Travelling',
  );
  final soon = FakeBookingRepository.sample(
    id: 'b5',
    reference: 'BK-2026-000014',
    status: BookingStatus.confirmed,
    startsIn: const Duration(hours: 10),
  );

  setUp(() {
    auth = FakeAuthRepository(
      signedInUser: const AppUser(id: 'u1', fullName: 'Sarah Khan'),
    );
    bookings = FakeBookingRepository(
      bookings: [upcoming, active, completed, cancelled, soon],
    );
    launcher = FakeLauncher();
  });
  tearDown(() => auth.dispose());

  Future<void> openBookings(WidgetTester tester) async {
    await pumpTestApp(
      tester,
      auth: auth,
      bookings: bookings,
      launcher: launcher,
    );
    await openTab(tester, _bookingsIcon);
  }

  Future<void> openBooking(WidgetTester tester, String reference) async {
    await tapAndSettle(tester, find.text(reference));
    expect(find.text('Progress'), findsOneWidget);
  }

  testWidgets('bookings are grouped into tabs', (tester) async {
    await openBookings(tester);

    // Upcoming: soonest first.
    expect(find.text('BK-2026-000014'), findsOneWidget);
    expect(find.text('BK-2026-000010'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('BK-2026-000014')).dy,
      lessThan(tester.getTopLeft(find.text('BK-2026-000010')).dy),
    );
    expect(find.text('BK-2026-000011'), findsNothing);

    await tapAndSettle(tester, find.text('Active'));
    expect(find.text('BK-2026-000011'), findsOneWidget);
    expect(find.text('Professional: Grace K.'), findsOneWidget);
    expect(find.text('In progress'), findsOneWidget);

    await tapAndSettle(tester, find.text('Completed'));
    expect(find.text('BK-2026-000012'), findsOneWidget);

    await tapAndSettle(tester, find.text('Cancelled').first);
    expect(find.text('BK-2026-000013'), findsOneWidget);
  });

  testWidgets('details show the professional, price and timeline', (
    tester,
  ) async {
    await openBookings(tester);
    await tapAndSettle(tester, find.text('Active'));
    await openBooking(tester, 'BK-2026-000011');

    expect(find.text('Your professional'), findsOneWidget);
    expect(find.text('Grace K.'), findsOneWidget);
    expect(find.text('5 years of experience'), findsOneWidget);
    expect(find.text('AED 90'), findsOneWidget);
    expect(find.text('1204, Tower 2, JLT, Dubai'), findsOneWidget);
    expect(find.text('Cash on completion'), findsOneWidget);
    // In progress: no changes in the app, but the team can be called.
    expect(find.text('Reschedule'), findsNothing);
    expect(find.text('Cancel booking'), findsNothing);
    expect(find.text('Call ${AgencyContact.phoneDisplay}'), findsOneWidget);
  });

  testWidgets('cancel an upcoming booking with a reason', (tester) async {
    await openBookings(tester);
    await openBooking(tester, 'BK-2026-000010');

    expect(find.text('Awaiting confirmation'), findsWidgets);
    expect(find.textContaining('free of charge until'), findsOneWidget);

    await tapAndSettle(tester, find.widgetWithText(AppButton, 'Cancel booking'));
    expect(find.text('Cancel this booking?'), findsOneWidget);

    // Keeping it changes nothing.
    await tapAndSettle(tester, find.text('Keep booking'));
    expect(bookings.cancelled, isEmpty);

    await tapAndSettle(tester, find.widgetWithText(AppButton, 'Cancel booking'));
    await tester.enterText(find.byType(TextField), 'Plans changed');
    await tapAndSettle(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Cancel booking'),
      ),
    );

    expect(bookings.cancelled, [('b1', 'Plans changed')]);
    expect(find.text('Booking cancelled.'), findsOneWidget);
    expect(find.text('Reason'), findsOneWidget);
    expect(find.text('Plans changed'), findsWidgets);
    expect(find.text('Reschedule'), findsNothing);
  });

  testWidgets('within 24 hours only a phone call can change it', (
    tester,
  ) async {
    await openBookings(tester);
    await openBooking(tester, 'BK-2026-000014');

    expect(find.text('Confirmed'), findsWidgets);
    expect(find.text('Reschedule'), findsNothing);
    expect(find.text('Cancel booking'), findsNothing);
    expect(find.textContaining('only be made by phone'), findsOneWidget);

    await tapAndSettle(
      tester,
      find.text('Call ${AgencyContact.phoneDisplay}'),
    );
    expect(launcher.opened.single, AgencyContact.callUri());
  });

  testWidgets('reschedule to a new time on the same day', (tester) async {
    await openBookings(tester);
    await openBooking(tester, 'BK-2026-000010');
    await tapAndSettle(tester, find.text('Reschedule'));

    expect(find.textContaining('Now: '), findsOneWidget);
    expect(_enabled(tester, 'Confirm new time'), isFalse);

    final day = toUae(upcoming.startsAt);
    final hour = day.hour == 10 ? 11 : 10;
    await tapAndSettle(tester, _chip(hour == 10 ? '10:00 AM' : '11:00 AM'));
    expect(_enabled(tester, 'Confirm new time'), isTrue);
    await tapAndSettle(tester, find.text('Confirm new time'));

    final expected = DateTime.utc(day.year, day.month, day.day, hour - 4);
    expect(bookings.rescheduled, [('b1', expected)]);
    // Back on the details: the agency confirms the new time again.
    expect(find.textContaining('Moved to'), findsOneWidget);
    expect(find.text('Progress'), findsOneWidget);
    expect(find.text('Rescheduled.'), findsOneWidget);
  });

  testWidgets('a time taken meanwhile is refused and the times refresh', (
    tester,
  ) async {
    await openBookings(tester);
    await openBooking(tester, 'BK-2026-000010');
    await tapAndSettle(tester, find.text('Reschedule'));

    final day = toUae(upcoming.startsAt);
    final hour = day.hour == 15 ? 16 : 15;
    final label = hour == 15 ? '3:00 PM' : '4:00 PM';
    await tapAndSettle(tester, _chip(label));

    bookings.takenHours.add(hour);
    await tapAndSettle(tester, find.text('Confirm new time'));

    expect(find.textContaining('just been taken'), findsOneWidget);
    expect(bookings.rescheduled, isEmpty);
    expect(_enabled(tester, 'Confirm new time'), isFalse);
    // The refreshed times show it as taken.
    expect(_chip(label), findsNothing);
    expect(find.text(label), findsOneWidget);
  });
}
