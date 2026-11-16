import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/supabase_providers.dart';
import '../../authentication/data/auth_providers.dart';
import '../domain/customer_notification.dart';

/// The signed-in customer's notifications.
///
/// Row Level Security lets customers read only their own notifications and
/// change nothing but the read time. New ones arrive live (Supabase
/// Realtime) while the app is open.
abstract interface class NotificationRepository {
  /// The latest notifications, newest first, updated live.
  Stream<List<CustomerNotification>> watch(String customerId);

  /// Marks [ids] as read, or all of them when [ids] is null.
  Future<void> markRead({List<int>? ids});
}

class SupabaseNotificationRepository implements NotificationRepository {
  SupabaseNotificationRepository(this._client);

  final SupabaseClient _client;

  /// How many notifications the list keeps.
  static const limit = 100;

  @override
  Stream<List<CustomerNotification>> watch(String customerId) => _client
      .from('customer_notifications')
      .stream(primaryKey: ['id'])
      .eq('customer_id', customerId)
      .order('created_at')
      .limit(limit)
      .map((rows) => rows.map(CustomerNotification.fromJson).toList())
      .handleError(
        (Object error, StackTrace stackTrace) =>
            Error.throwWithStackTrace(AppFailure.from(error), stackTrace),
      );

  @override
  Future<void> markRead({List<int>? ids}) async {
    try {
      await _client.rpc<void>(
        'mark_customer_notifications_read',
        params: {'p_ids': ids},
      );
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(AppFailure.from(error), stackTrace);
    }
  }
}

/// Used when the app has no Supabase settings: no notifications.
class UnavailableNotificationRepository implements NotificationRepository {
  const UnavailableNotificationRepository();

  @override
  Stream<List<CustomerNotification>> watch(String customerId) =>
      Stream.value(const []);

  @override
  Future<void> markRead({List<int>? ids}) async {}
}

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  if (!Env.isSupabaseConfigured) {
    return const UnavailableNotificationRepository();
  }
  return SupabaseNotificationRepository(ref.watch(supabaseClientProvider));
});

/// The signed-in customer's notifications, newest first (empty for guests).
final customerNotificationsProvider =
    StreamProvider<List<CustomerNotification>>((ref) async* {
      final user = await ref.watch(authStateProvider.future);
      if (user == null) {
        yield const <CustomerNotification>[];
        return;
      }
      yield* ref.watch(notificationRepositoryProvider).watch(user.id);
    });

/// Notifications marked read on this device, shown as read straight away
/// (before the live update from the server arrives).
class NotificationReads extends Notifier<({Set<int> ids, DateTime? allAt})> {
  @override
  ({Set<int> ids, DateTime? allAt}) build() {
    // Start fresh when the signed-in user changes.
    ref.watch(authStateProvider);
    return (ids: const <int>{}, allAt: null);
  }

  void add(int id) => state = (ids: {...state.ids, id}, allAt: state.allAt);

  void markAll() => state = (ids: state.ids, allAt: DateTime.now());
}

final notificationReadsProvider =
    NotifierProvider<NotificationReads, ({Set<int> ids, DateTime? allAt})>(
      NotificationReads.new,
    );

/// The list as shown: server data plus reads made on this device.
final notificationListProvider =
    Provider<AsyncValue<List<CustomerNotification>>>((ref) {
      final reads = ref.watch(notificationReadsProvider);
      final allAt = reads.allAt;
      final server = ref.watch(customerNotificationsProvider);
      final list = server.value;
      if (list == null) return server;
      return AsyncData([
        for (final n in list)
          if (n.isUnread &&
              (reads.ids.contains(n.id) ||
                  (allAt != null && !n.createdAt.isAfter(allAt))))
            n.markedRead(allAt ?? DateTime.now())
          else
            n,
      ]);
    });

/// Unread notifications, for the badge on the Home bell.
final unreadNotificationCountProvider = Provider<int>(
  (ref) =>
      ref
          .watch(notificationListProvider)
          .value
          ?.where((n) => n.isUnread)
          .length ??
      0,
);
