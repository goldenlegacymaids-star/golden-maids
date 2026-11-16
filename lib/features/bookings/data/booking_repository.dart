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

  /// Creates a booking and returns its reference (BK-…).
  Future<String> createBooking(BookingDraft draft);
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

  @override
  Future<String> createBooking(BookingDraft draft) => _guard(() async {
    final row = await _client
        .from('bookings')
        .insert(draft.toInsertJson())
        .select('reference')
        .single();
    return row['reference'] as String;
  });
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
  Future<String> createBooking(BookingDraft draft) => Future.error(_failure);
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
