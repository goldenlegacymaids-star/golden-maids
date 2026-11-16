import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/supabase_providers.dart';
import '../../authentication/data/auth_providers.dart';
import '../domain/booking.dart';

/// Home-service bookings for the signed-in customer.
///
/// The database checks everything again when a booking is made: working
/// hours, notice, the booking window, free staff for the slot, and the
/// price estimate. The app's checks only make the screen friendlier.
abstract interface class BookingRepository {
  Future<BookingSettings> getSettings();

  /// Start times for a service on a UAE date ([hours] for hourly services).
  Future<List<TimeSlot>> getSlots({
    required String serviceId,
    required DateTime day,
    int? hours,
  });

  /// The customer's saved UAE addresses (default first).
  Future<List<SavedAddress>> getSavedAddresses();

  /// Saves an address and returns it.
  Future<SavedAddress> saveAddress(AddressInput address);

  /// Changes a saved address (Profile → Saved Addresses).
  Future<void> updateAddress(String id, AddressInput address);

  /// Deletes a saved address. Bookings keep their own copy of it.
  Future<void> deleteAddress(String id);

  /// Makes an address the default (the previous default is cleared).
  Future<void> setDefaultAddress(String id);

  /// Creates a booking and returns its reference (BK-…).
  Future<String> createBooking(BookingDraft draft);

  /// The signed-in customer's bookings, newest start first.
  Future<List<Booking>> getMyBookings();

  Future<Booking> getBooking(String id);

  /// The timeline the customer may see, oldest first.
  Future<List<BookingEvent>> getHistory(String bookingId);

  /// Cancels (until the cancellation limit; the database checks it).
  Future<void> cancelBooking(String id, {String reason = ''});

  /// Moves the booking to a new start time; the agency confirms it again.
  Future<void> rescheduleBooking(String id, DateTime startsAt);
}

class SupabaseBookingRepository implements BookingRepository {
  SupabaseBookingRepository(this._client);

  final SupabaseClient _client;

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(AppFailure.from(error), stackTrace);
    }
  }

  String _userId() {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw const AuthFailure();
    }
    return id;
  }

  @override
  Future<BookingSettings> getSettings() => _guard(() async {
    final row = await _client
        .from('booking_settings')
        .select(BookingSettings.columns)
        .maybeSingle();
    return row == null ? const BookingSettings() : BookingSettings.fromJson(row);
  });

  @override
  Future<List<TimeSlot>> getSlots({
    required String serviceId,
    required DateTime day,
    int? hours,
  }) => _guard(() async {
    final result = await _client.rpc<dynamic>(
      'available_slots',
      params: {
        'p_service_id': serviceId,
        'p_date': isoDate(day),
        'p_hours': hours,
      },
    );
    final rows = result as List<dynamic>? ?? const [];
    return [
      for (final row in rows) TimeSlot.fromJson(row as Map<String, dynamic>),
    ];
  });

  @override
  Future<List<SavedAddress>> getSavedAddresses() => _guard(() async {
    // Booking staff can read every address, so the customer's own are
    // selected explicitly.
    final rows = await _client
        .from('addresses')
        .select(SavedAddress.columns)
        .eq('user_id', _userId())
        .eq('country_code', 'AE')
        .order('is_default', ascending: false)
        .order('created_at', ascending: false);
    return rows.map(SavedAddress.fromJson).toList();
  });

  @override
  Future<SavedAddress> saveAddress(AddressInput address) => _guard(() async {
    final row = await _client
        .from('addresses')
        .insert(address.toInsertJson())
        .select(SavedAddress.columns)
        .single();
    return SavedAddress.fromJson(row);
  });

  /// Changes one of the customer's addresses; a refused change returns no
  /// rows rather than an error.
  Future<void> _changeAddress(
    Future<PostgrestList> Function(String userId) change,
  ) async {
    final rows = await change(_userId());
    if (rows.isEmpty) throw const NotFoundFailure();
  }

  @override
  Future<void> updateAddress(String id, AddressInput address) => _guard(
    () => _changeAddress(
      (userId) => _client
          .from('addresses')
          .update(address.toUpdateJson())
          .eq('id', id)
          .eq('user_id', userId)
          .select('id'),
    ),
  );

  @override
  Future<void> deleteAddress(String id) => _guard(
    () => _changeAddress(
      (userId) => _client
          .from('addresses')
          .delete()
          .eq('id', id)
          .eq('user_id', userId)
          .select('id'),
    ),
  );

  @override
  Future<void> setDefaultAddress(String id) => _guard(
    () => _changeAddress(
      (userId) => _client
          .from('addresses')
          .update({'is_default': true})
          .eq('id', id)
          .eq('user_id', userId)
          .select('id'),
    ),
  );

  @override
  Future<String> createBooking(BookingDraft draft) => _guard(() async {
    final row = await _client
        .from('bookings')
        .insert(draft.toInsertJson())
        .select('reference')
        .single();
    return row['reference'] as String;
  });

  @override
  Future<List<Booking>> getMyBookings() => _guard(() async {
    // Booking staff can read every booking, so the customer's own are
    // selected explicitly.
    final rows = await _client
        .from('bookings')
        .select(Booking.columns)
        .eq('customer_id', _userId())
        .order('starts_at', ascending: false);
    return rows.map(Booking.fromJson).toList();
  });

  @override
  Future<Booking> getBooking(String id) => _guard(() async {
    final row = await _client
        .from('bookings')
        .select(Booking.columns)
        .eq('id', id)
        .eq('customer_id', _userId())
        .maybeSingle();
    if (row == null) throw const NotFoundFailure();
    return Booking.fromJson(row);
  });

  @override
  Future<List<BookingEvent>> getHistory(String bookingId) => _guard(() async {
    final rows = await _client
        .from('booking_history')
        .select('status, note, created_at')
        .eq('booking_id', bookingId)
        .eq('is_customer_visible', true)
        .order('created_at', ascending: true)
        .order('id', ascending: true);
    return rows.map(BookingEvent.fromJson).toList();
  });

  Future<void> _update(String id, Map<String, dynamic> values) async {
    // A refused change returns no rows rather than an error.
    final rows = await _client
        .from('bookings')
        .update(values)
        .eq('id', id)
        .eq('customer_id', _userId())
        .select('id');
    if (rows.isEmpty) throw const NotFoundFailure();
  }

  @override
  Future<void> cancelBooking(String id, {String reason = ''}) =>
      _guard(() => _update(id, {
        'status': BookingStatus.cancelled.value,
        'cancel_reason': reason.trim(),
      }));

  @override
  Future<void> rescheduleBooking(String id, DateTime startsAt) => _guard(
    () => _update(id, {'starts_at': startsAt.toUtc().toIso8601String()}),
  );
}

/// Used when the app has no Supabase settings.
class UnavailableBookingRepository implements BookingRepository {
  const UnavailableBookingRepository();

  static const _failure = ServerFailure(
    message: 'Bookings are unavailable: the app is not connected to its '
        'server.',
  );

  @override
  Future<BookingSettings> getSettings() => Future.error(_failure);

  @override
  Future<List<TimeSlot>> getSlots({
    required String serviceId,
    required DateTime day,
    int? hours,
  }) => Future.error(_failure);

  @override
  Future<List<SavedAddress>> getSavedAddresses() => Future.error(_failure);

  @override
  Future<SavedAddress> saveAddress(AddressInput address) =>
      Future.error(_failure);

  @override
  Future<void> updateAddress(String id, AddressInput address) =>
      Future.error(_failure);

  @override
  Future<void> deleteAddress(String id) => Future.error(_failure);

  @override
  Future<void> setDefaultAddress(String id) => Future.error(_failure);

  @override
  Future<String> createBooking(BookingDraft draft) => Future.error(_failure);

  @override
  Future<List<Booking>> getMyBookings() => Future.error(_failure);

  @override
  Future<Booking> getBooking(String id) => Future.error(_failure);

  @override
  Future<List<BookingEvent>> getHistory(String bookingId) =>
      Future.error(_failure);

  @override
  Future<void> cancelBooking(String id, {String reason = ''}) =>
      Future.error(_failure);

  @override
  Future<void> rescheduleBooking(String id, DateTime startsAt) =>
      Future.error(_failure);
}

final bookingRepositoryProvider = Provider<BookingRepository>((ref) {
  if (!Env.isSupabaseConfigured) return const UnavailableBookingRepository();
  return SupabaseBookingRepository(ref.watch(supabaseClientProvider));
});

final bookingSettingsProvider = FutureProvider<BookingSettings>(
  (ref) => ref.watch(bookingRepositoryProvider).getSettings(),
  isAutoDispose: true,
);

/// Slots for (service id, UAE date as yyyy-MM-dd, hours or null).
final timeSlotsProvider =
    FutureProvider.family<List<TimeSlot>, (String, String, int?)>(
      (ref, key) {
        final (serviceId, date, hours) = key;
        return ref
            .watch(bookingRepositoryProvider)
            .getSlots(
              serviceId: serviceId,
              day: DateTime.parse(date),
              hours: hours,
            );
      },
      isAutoDispose: true,
    );

/// The signed-in customer's saved addresses (empty for guests).
final savedAddressesProvider = FutureProvider<List<SavedAddress>>(
  (ref) async {
    final user = await ref.watch(authStateProvider.future);
    if (user == null) return const <SavedAddress>[];
    return ref.watch(bookingRepositoryProvider).getSavedAddresses();
  },
  isAutoDispose: true,
);

/// The signed-in customer's bookings (empty for guests).
final myBookingsProvider = FutureProvider<List<Booking>>(
  (ref) async {
    final user = await ref.watch(authStateProvider.future);
    if (user == null) return const <Booking>[];
    return ref.watch(bookingRepositoryProvider).getMyBookings();
  },
  isAutoDispose: true,
);

final bookingProvider = FutureProvider.family<Booking, String>(
  (ref, id) => ref.watch(bookingRepositoryProvider).getBooking(id),
  isAutoDispose: true,
);

final bookingHistoryProvider =
    FutureProvider.family<List<BookingEvent>, String>(
      (ref, id) => ref.watch(bookingRepositoryProvider).getHistory(id),
      isAutoDispose: true,
    );
