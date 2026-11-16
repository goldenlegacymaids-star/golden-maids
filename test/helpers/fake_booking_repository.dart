import 'package:golden_maids/core/errors/app_failure.dart';
import 'package:golden_maids/features/bookings/data/booking_repository.dart';
import 'package:golden_maids/features/bookings/domain/booking.dart';

/// In-memory [BookingRepository]: hourly slots from 8 am to 8 pm UAE time,
/// all free except the [takenHours].
class FakeBookingRepository implements BookingRepository {
  FakeBookingRepository({
    this.settings = const BookingSettings(),
    List<SavedAddress>? addresses,
  }) : addresses = [...?addresses];

  final BookingSettings settings;
  final List<SavedAddress> addresses;

  /// UAE start hours (e.g. 9 for 9 am) shown as taken.
  final Set<int> takenHours = {};

  /// Bookings created, in order.
  final List<BookingDraft> created = [];

  /// Addresses saved, in order.
  final List<AddressInput> savedInputs = [];

  /// Slot requests, as (service id, date, hours).
  final List<(String, String, int?)> slotRequests = [];

  /// When set, the next booking fails with this error (then succeeds).
  AppFailure? bookingFailure;

  @override
  Future<BookingSettings> getSettings() async => settings;

  @override
  Future<List<TimeSlot>> getSlots({
    required String serviceId,
    required DateTime day,
    int? hours,
  }) async {
    slotRequests.add((serviceId, isoDate(day), hours));
    final length = hours ?? 1;
    return [
      for (var hour = 8; hour + length <= 20; hour++)
        TimeSlot(
          // UAE is UTC+4.
          startsAt: DateTime.utc(day.year, day.month, day.day, hour - 4),
          isAvailable: !takenHours.contains(hour),
        ),
    ];
  }

  @override
  Future<List<SavedAddress>> getSavedAddresses() async => [...addresses];

  @override
  Future<SavedAddress> saveAddress(AddressInput address) async {
    savedInputs.add(address);
    final saved = SavedAddress(
      id: 'addr-${savedInputs.length}',
      label: address.label,
      emirate: address.emirate,
      area: address.area,
      building: address.building,
      apartment: address.apartment,
      instructions: address.notes,
    );
    addresses.add(saved);
    return saved;
  }

  @override
  Future<String> createBooking(BookingDraft draft) async {
    final failure = bookingFailure;
    if (failure != null) {
      bookingFailure = null;
      throw failure;
    }
    created.add(draft);
    return 'BK-2026-${created.length.toString().padLeft(6, '0')}';
  }
}
