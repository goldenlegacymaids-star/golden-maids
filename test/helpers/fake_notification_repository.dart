import 'dart:async';

import 'package:golden_maids/features/notifications/data/notification_repository.dart';
import 'package:golden_maids/features/notifications/domain/customer_notification.dart';

/// In-memory [NotificationRepository]: the list updates "live" like the
/// real one when notifications are added or marked read.
class FakeNotificationRepository implements NotificationRepository {
  FakeNotificationRepository({List<CustomerNotification>? notifications})
    : notifications = [...?notifications];

  final List<CustomerNotification> notifications;
  final _changes = StreamController<void>.broadcast();

  /// Calls to [markRead]: the ids, or null for "all".
  final List<List<int>?> markReadCalls = [];

  /// Simulates a new notification arriving from the agency.
  void push(CustomerNotification notification) {
    notifications.insert(0, notification);
    _changes.add(null);
  }

  @override
  Stream<List<CustomerNotification>> watch(String customerId) async* {
    yield List.of(notifications);
    await for (final _ in _changes.stream) {
      yield List.of(notifications);
    }
  }

  @override
  Future<void> markRead({List<int>? ids}) async {
    markReadCalls.add(ids);
    final now = DateTime.now();
    for (var i = 0; i < notifications.length; i++) {
      if (ids == null || ids.contains(notifications[i].id)) {
        notifications[i] = notifications[i].markedRead(now);
      }
    }
    _changes.add(null);
  }

  Future<void> dispose() => _changes.close();

  static CustomerNotification sample({
    required int id,
    String kind = 'hiring.shortlisted',
    String title = 'Maids shortlisted',
    String body = 'We’ve shortlisted maids for your request.',
    String? bookingId,
    String? hiringRequestId,
    String? candidateId,
    bool read = false,
    DateTime? createdAt,
  }) => CustomerNotification(
    id: id,
    kind: kind,
    title: title,
    body: body,
    createdAt: createdAt ?? DateTime.now().subtract(const Duration(minutes: 5)),
    bookingId: bookingId,
    hiringRequestId: hiringRequestId,
    candidateId: candidateId,
    readAt: read ? DateTime.now() : null,
  );
}
