import 'package:golden_maids/core/errors/app_failure.dart';
import 'package:golden_maids/features/bookings/data/booking_repository.dart';
import 'package:golden_maids/features/bookings/domain/booking.dart';

/// In-memory [BookingRepository]: hourly slots from 8 am to 8 pm UAE time,
/// all free except the [takenHours].
class FakeBookingRepository implements BookingRepository {
  FakeBookingRepository({
    this.settings = const BookingSettings(),
    List<SavedAddress>? addresses,
    List<Booking>? bookings,
  }) : addresses = [...?addresses],
       bookings = [...?bookings];

  final BookingSettings settings;
  final List<SavedAddress> addresses;

  /// The customer's bookings (for My Bookings).
  final List<Booking> bookings;

  /// Timelines by booking id (a single "booked" step when missing).
  final Map<String, List<BookingEvent>> history = {};

  /// Cancellations made, as (booking id, reason).
  final List<(String, String)> cancelled = [];

  /// Reschedules made, as (booking id, new start).
  final List<(String, DateTime)> rescheduled = [];

  /// A booking for My Bookings; starts [startsIn] from now.
  static Booking sample({
    required String id,
    required String reference,
    BookingStatus status = BookingStatus.pending,
    Duration startsIn = const Duration(days: 3),
    int? hours = 2,
    String serviceName = 'Hourly Maid',
    String serviceId = 's3',
    BookingType type = BookingType.hourly,
    double? price = 90,
    String? staffName,
    int? staffYears,
    String cancelReason = '',
  }) {
    final now = DateTime.now().toUtc();
    final start = DateTime.utc(
      now.year,
      now.month,
      now.day,
      now.hour,
    ).add(startsIn);
    return Booking(
      id: id,
      reference: reference,
      serviceId: serviceId,
      serviceName: serviceName,
      bookingType: type,
      hours: hours,
      startsAt: start,
      endsAt: start.add(Duration(hours: hours ?? 1)),
      emirate: 'Dubai',
      area: 'JLT',
      building: 'Tower 2',
      apartment: '1204',
      customerName: 'Sarah Khan',
      customerPhone: '+971501234567',
      priceEstimate: price,
      status: status,
      staffName: staffName,
      staffYearsExperience: staffYears,
      cancelReason: cancelReason,
      createdAt: now.subtract(const Duration(days: 1)),
    );
  }

  static Booking _copy(
    Booking b, {
    BookingStatus? status,
    DateTime? startsAt,
    String? cancelReason,
    bool keepStaff = true,
  }) {
    final start = startsAt ?? b.startsAt;
    return Booking(
      id: b.id,
      reference: b.reference,
      serviceId: b.serviceId,
      serviceName: b.serviceName,
      bookingType: b.bookingType,
      hours: b.hours,
      startsAt: start,
      endsAt: start.add(b.endsAt.difference(b.startsAt)),
      emirate: b.emirate,
      area: b.area,
      building: b.building,
      apartment: b.apartment,
      addressNotes: b.addressNotes,
      instructions: b.instructions,
      customerName: b.customerName,
      customerPhone: b.customerPhone,
      priceEstimate: b.priceEstimate,
      priceUnit: b.priceUnit,
      paymentMethod: b.paymentMethod,
      status: status ?? b.status,
      staffName: keepStaff ? b.staffName : null,
      staffYearsExperience: keepStaff ? b.staffYearsExperience : null,
      cancelReason: cancelReason ?? b.cancelReason,
      createdAt: b.createdAt,
    );
  }

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

  /// Default first, as the database orders them.
  @override
  Future<List<SavedAddress>> getSavedAddresses() async => [
    ...addresses.where((a) => a.isDefault),
    ...addresses.where((a) => !a.isDefault),
  ];

  static SavedAddress _address(String id, AddressInput input) => SavedAddress(
    id: id,
    label: input.label,
    emirate: input.emirate,
    area: input.area,
    building: input.building,
    apartment: input.apartment,
    instructions: input.notes,
    isDefault: input.isDefault,
  );

  /// Only one default, as in the database.
  void _clearOtherDefaults(String id) {
    for (var i = 0; i < addresses.length; i++) {
      final a = addresses[i];
      if (a.id != id && a.isDefault) {
        addresses[i] = _address(a.id, a.toInput().withDefault(false));
      }
    }
  }

  int _addressIndex(String id) {
    final index = addresses.indexWhere((a) => a.id == id);
    if (index < 0) throw const NotFoundFailure();
    return index;
  }

  @override
  Future<SavedAddress> saveAddress(AddressInput address) async {
    savedInputs.add(address);
    final saved = _address('addr-${savedInputs.length}', address);
    addresses.add(saved);
    if (saved.isDefault) _clearOtherDefaults(saved.id);
    return saved;
  }

  /// Address updates, as (id, new values).
  final List<(String, AddressInput)> updatedAddresses = [];

  @override
  Future<void> updateAddress(String id, AddressInput address) async {
    final index = _addressIndex(id);
    updatedAddresses.add((id, address));
    addresses[index] = _address(id, address);
    if (address.isDefault) _clearOtherDefaults(id);
  }

  @override
  Future<void> deleteAddress(String id) async {
    addresses.removeAt(_addressIndex(id));
  }

  @override
  Future<void> setDefaultAddress(String id) async {
    final index = _addressIndex(id);
    addresses[index] = _address(
      id,
      addresses[index].toInput().withDefault(true),
    );
    _clearOtherDefaults(id);
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

  int _index(String id) {
    final index = bookings.indexWhere((b) => b.id == id);
    if (index < 0) throw const NotFoundFailure();
    return index;
  }

  /// Same rule and message as the database.
  void _checkCanChange(Booking booking) {
    if (!booking.canChange(settings)) {
      throw const PermissionFailure(
        message:
            'This booking can no longer be changed in the app. Please call '
            'us on +971 4 323 4393.',
      );
    }
  }

  void _addEvent(String id, BookingStatus status, [String note = '']) {
    history
        .putIfAbsent(id, () => [])
        .add(
          BookingEvent(status: status, note: note, createdAt: DateTime.now()),
        );
  }

  @override
  Future<List<Booking>> getMyBookings() async => [...bookings];

  @override
  Future<Booking> getBooking(String id) async => bookings[_index(id)];

  @override
  Future<List<BookingEvent>> getHistory(String bookingId) async {
    final booking = bookings[_index(bookingId)];
    return [
      ...history[bookingId] ??
          [
            BookingEvent(
              status: BookingStatus.pending,
              createdAt: booking.createdAt,
            ),
          ],
    ];
  }

  @override
  Future<void> cancelBooking(String id, {String reason = ''}) async {
    final index = _index(id);
    _checkCanChange(bookings[index]);
    cancelled.add((id, reason));
    bookings[index] = _copy(
      bookings[index],
      status: BookingStatus.cancelled,
      cancelReason: reason,
    );
    _addEvent(id, BookingStatus.cancelled, reason);
  }

  @override
  Future<void> rescheduleBooking(String id, DateTime startsAt) async {
    final index = _index(id);
    _checkCanChange(bookings[index]);
    final uae = toUae(startsAt);
    if (takenHours.contains(uae.hour)) {
      throw const ValidationFailure(
        message:
            'Sorry, this slot has just been taken. Please choose another time.',
      );
    }
    rescheduled.add((id, startsAt));
    // The agency confirms the new time and assigns staff again.
    bookings[index] = _copy(
      bookings[index],
      status: BookingStatus.pending,
      startsAt: startsAt,
      keepStaff: false,
    );
    _addEvent(id, BookingStatus.pending, 'Rescheduled.');
  }
}
