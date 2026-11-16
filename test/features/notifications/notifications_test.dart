import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_maids/core/widgets/app_icon_button.dart';
import 'package:golden_maids/features/authentication/domain/auth_repository.dart';
import 'package:golden_maids/features/notifications/domain/customer_notification.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_hiring_repository.dart';
import '../../helpers/fake_notification_repository.dart';
import '../../helpers/test_app.dart';

/// Whether the Home bell shows its unread dot.
bool _bellHasBadge(WidgetTester tester) => tester
    .widget<AppIconButton>(
      find.ancestor(
        of: find.byIcon(Icons.notifications_none_rounded),
        matching: find.byType(AppIconButton),
      ),
    )
    .showBadge;

void main() {
  late FakeAuthRepository auth;
  late FakeNotificationRepository notifications;
  late FakeHiringRepository hiring;

  setUp(() {
    auth = FakeAuthRepository(
      signedInUser: const AppUser(id: 'u1', fullName: 'Sarah Khan'),
    );
    hiring = FakeHiringRepository(
      requests: [
        FakeHiringRepository.sample(id: 'r1', reference: 'HR-2026-000010'),
      ],
    );
    notifications = FakeNotificationRepository(
      notifications: [
        FakeNotificationRepository.sample(
          id: 2,
          hiringRequestId: 'r1',
          body: 'We’ve shortlisted maids for your request HR-2026-000010.',
        ),
        FakeNotificationRepository.sample(
          id: 1,
          kind: 'booking.confirmed',
          title: 'Booking confirmed',
          body: 'Your Home Cleaning is confirmed.',
          read: true,
          createdAt: DateTime.now().subtract(const Duration(days: 1)),
        ),
      ],
    );
  });
  tearDown(() async {
    await auth.dispose();
    await notifications.dispose();
  });

  Future<void> start(WidgetTester tester) => pumpTestApp(
    tester,
    auth: auth,
    hiring: hiring,
    notifications: notifications,
  );

  testWidgets('the bell shows a dot while something is unread', (
    tester,
  ) async {
    await start(tester);
    expect(_bellHasBadge(tester), isTrue);

    await notifications.markRead();
    await settle(tester);
    expect(_bellHasBadge(tester), isFalse);

    // A new update from the agency arrives while the app is open.
    notifications.push(
      FakeNotificationRepository.sample(id: 3, title: 'Interview scheduled'),
    );
    await settle(tester);
    expect(_bellHasBadge(tester), isTrue);
  });

  testWidgets('lists updates; tapping one marks it read and opens it', (
    tester,
  ) async {
    await start(tester);
    await tapAndSettle(tester, find.byTooltip('Notifications'));

    expect(find.text('Maids shortlisted'), findsOneWidget);
    expect(find.text('Booking confirmed'), findsOneWidget);
    expect(find.text('5 min ago'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(find.text('Mark all read'), findsOneWidget);

    await tapAndSettle(tester, find.text('Maids shortlisted'));
    expect(notifications.markReadCalls, [
      [2],
    ]);
    // The request's details screen.
    expect(find.text('Status'), findsOneWidget);
  });

  testWidgets('mark all read', (tester) async {
    await start(tester);
    await tapAndSettle(tester, find.byTooltip('Notifications'));

    await tapAndSettle(tester, find.text('Mark all read'));
    expect(notifications.markReadCalls, [null]);
    expect(find.text('Mark all read'), findsNothing);
  });

  testWidgets('guests are asked to sign in', (tester) async {
    await pumpTestApp(tester, auth: FakeAuthRepository());
    await tapAndSettle(tester, find.byTooltip('Notifications'));

    expect(find.text('Sign in to see updates'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
  });

  test('times read naturally', () {
    final now = DateTime(2026, 11, 16, 18);
    expect(notificationTime(now, now: now), 'Just now');
    expect(
      notificationTime(now.subtract(const Duration(minutes: 7)), now: now),
      '7 min ago',
    );
    expect(
      notificationTime(now.subtract(const Duration(hours: 3)), now: now),
      '3 h ago',
    );
    expect(notificationTime(DateTime(2026, 11, 15, 22), now: now), 'Yesterday');
    expect(notificationTime(DateTime(2026, 11, 2, 9), now: now), '2 Nov');
    expect(notificationTime(DateTime(2025, 12, 30), now: now), '30 Dec 2025');
  });

  test('topic comes from the kind', () {
    expect(
      FakeNotificationRepository.sample(id: 1, kind: 'enquiry.closed').topic,
      NotificationTopic.enquiry,
    );
    expect(
      FakeNotificationRepository.sample(id: 1, kind: 'booking.note').topic,
      NotificationTopic.booking,
    );
  });
}
