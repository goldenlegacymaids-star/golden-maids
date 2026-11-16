import '../../services/domain/catalog.dart';

// How a service is booked and priced, for every booking file.
export '../../services/domain/catalog.dart' show BookingType, PriceUnit;

/// How the customer pays (on completion, for now).
enum PaymentMethod {
  cash('cash', 'Cash on completion'),
  cardOnCompletion('card_on_completion', 'Card on completion');

  const PaymentMethod(this.value, this.label);

  final String value;
  final String label;
}

/// The UAE is UTC+4 all year (no daylight saving).
const Duration uaeOffset = Duration(hours: 4);

/// [instant] as UAE wall-clock time (read its fields, not its time zone).
DateTime toUae(DateTime instant) => instant.toUtc().add(uaeOffset);

/// Today's date in the UAE (time set to midnight).
DateTime uaeToday([DateTime? now]) {
  final uae = toUae(now ?? DateTime.now());
  return DateTime(uae.year, uae.month, uae.day);
}

/// `2026-11-20`
String isoDate(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-'
    '${day.month.toString().padLeft(2, '0')}-'
    '${day.day.toString().padLeft(2, '0')}';

/// Working hours and booking rules (`public.booking_settings`).
class BookingSettings {
  const BookingSettings({
    this.openMinutes = 8 * 60,
    this.closeMinutes = 20 * 60,
    this.openDays = const [1, 2, 3, 4, 5, 6, 7],
    this.slotMinutes = 60,
    this.minHours = 2,
    this.maxHours = 8,
    this.minNoticeHours = 3,
    this.windowDays = 30,
    this.cancelHours = 24,
    this.defaultVisitMinutes = 240,
  });

  factory BookingSettings.fromJson(Map<String, dynamic> json) {
    return BookingSettings(
      openMinutes: _minutes(json['open_time'] as String?, 8 * 60),
      closeMinutes: _minutes(json['close_time'] as String?, 20 * 60),
      openDays: [
        for (final day in (json['open_days'] as List<dynamic>? ?? const []))
          day as int,
      ],
      slotMinutes: json['slot_minutes'] as int? ?? 60,
      minHours: json['min_hours'] as int? ?? 2,
      maxHours: json['max_hours'] as int? ?? 8,
      minNoticeHours: json['min_notice_hours'] as int? ?? 3,
      windowDays: json['window_days'] as int? ?? 30,
      cancelHours: json['cancel_hours'] as int? ?? 24,
      defaultVisitMinutes: json['default_visit_minutes'] as int? ?? 240,
    );
  }

  static const String columns =
      'open_time, close_time, open_days, slot_minutes, min_hours, max_hours, '
      'min_notice_hours, window_days, cancel_hours, default_visit_minutes';

  /// "08:00:00" → 480
  static int _minutes(String? time, int fallback) {
    if (time == null) return fallback;
    final parts = time.split(':');
    if (parts.length < 2) return fallback;
    final hours = int.tryParse(parts[0]);
    final minutes = int.tryParse(parts[1]);
    if (hours == null || minutes == null) return fallback;
    return hours * 60 + minutes;
  }

  /// Opening time, in minutes after midnight (UAE).
  final int openMinutes;
  final int closeMinutes;

  /// ISO weekdays (1 = Monday … 7 = Sunday), like `DateTime.weekday`.
  final List<int> openDays;
  final int slotMinutes;
  final int minHours;
  final int maxHours;
  final int minNoticeHours;
  final int windowDays;
  final int cancelHours;
  final int defaultVisitMinutes;

  /// The days a customer can choose (UAE dates), starting today.
  List<DateTime> bookableDays([DateTime? now]) {
    final today = uaeToday(now);
    return [
      for (var i = 0; i <= windowDays; i++)
        DateTime(today.year, today.month, today.day + i),
    ];
  }

  bool isOpenOn(DateTime day) => openDays.contains(day.weekday);
}

/// A start time on the booking screen.
class TimeSlot {
  const TimeSlot({required this.startsAt, required this.isAvailable});

  factory TimeSlot.fromJson(Map<String, dynamic> json) {
    return TimeSlot(
      startsAt: DateTime.parse(json['starts_at'] as String),
      isAvailable: json['is_available'] as bool? ?? false,
    );
  }

  final DateTime startsAt;
  final bool isAvailable;
}

/// A customer's saved address (`public.addresses`, UAE only for now).
class SavedAddress {
  const SavedAddress({
    required this.id,
    required this.label,
    required this.emirate,
    required this.area,
    required this.building,
    this.apartment = '',
    this.instructions = '',
  });

  factory SavedAddress.fromJson(Map<String, dynamic> json) {
    return SavedAddress(
      id: json['id'] as String,
      label: json['label'] as String? ?? 'Home',
      emirate: json['region'] as String,
      area: json['area'] as String,
      building: json['building'] as String,
      apartment: json['apartment'] as String? ?? '',
      instructions: json['instructions'] as String? ?? '',
    );
  }

  static const String columns =
      'id, label, region, area, building, apartment, instructions';

  final String id;
  final String label;
  final String emirate;
  final String area;
  final String building;
  final String apartment;
  final String instructions;

  /// "Apt 1204, Tower 1, JLT, Dubai"
  String get summary => [
    if (apartment.isNotEmpty) 'Apt $apartment',
    building,
    area,
    emirate,
  ].join(', ');
}

/// A new address typed in on the booking screen.
class AddressInput {
  const AddressInput({
    required this.emirate,
    required this.area,
    required this.building,
    this.apartment = '',
    this.notes = '',
    this.label = 'Home',
  });

  final String emirate;
  final String area;
  final String building;
  final String apartment;
  final String notes;
  final String label;

  Map<String, dynamic> toInsertJson() => {
    'label': label,
    'country_code': 'AE',
    'region': emirate,
    'area': area,
    'building': building,
    'apartment': apartment.isEmpty ? null : apartment,
    'instructions': notes.isEmpty ? null : notes,
  };
}

/// Everything sent when the customer confirms a booking.
class BookingDraft {
  const BookingDraft({
    required this.serviceId,
    required this.startsAt,
    required this.address,
    required this.customerName,
    required this.customerPhone,
    this.hours,
    this.addressId,
    this.instructions = '',
    this.paymentMethod = PaymentMethod.cash,
  });

  final String serviceId;

  /// Hourly services only.
  final int? hours;
  final DateTime startsAt;

  /// The saved address used, if any (the details are still sent as a
  /// snapshot, so the booking keeps them if the address changes later).
  final String? addressId;
  final AddressInput address;
  final String instructions;
  final String customerName;
  final String customerPhone;
  final PaymentMethod paymentMethod;

  Map<String, dynamic> toInsertJson() => {
    'service_id': serviceId,
    'hours': hours,
    'starts_at': startsAt.toUtc().toIso8601String(),
    'address_id': addressId,
    'emirate': address.emirate,
    'area': address.area,
    'building': address.building,
    'apartment': address.apartment,
    'address_notes': address.notes,
    'instructions': instructions,
    'customer_name': customerName,
    'customer_phone': customerPhone,
    'payment_method': paymentMethod.value,
  };
}

/// The estimate the database will store (null = confirmed by the agency).
double? priceEstimate(HomeService service, int? hours) {
  final price = service.basePrice;
  if (price == null) return null;
  if (service.bookingType == BookingType.hourly &&
      service.priceUnit == PriceUnit.perHour &&
      hours != null) {
    return price * hours;
  }
  return price;
}

/// Length of the job in minutes, as the database computes it.
int jobMinutes(HomeService service, BookingSettings settings, int? hours) {
  return switch (service.bookingType) {
    BookingType.hourly => (hours ?? settings.minHours) * 60,
    BookingType.visit => service.durationMinutes ?? settings.defaultVisitMinutes,
    BookingType.request => 60,
  };
}

/// Where a booking is (`bookings.status`).
enum BookingStatus {
  pending('pending', 'Awaiting confirmation'),
  confirmed('confirmed', 'Confirmed'),
  providerAssigned('provider_assigned', 'Professional assigned'),
  onTheWay('on_the_way', 'On the way'),
  inProgress('in_progress', 'In progress'),
  completed('completed', 'Completed'),
  cancelled('cancelled', 'Cancelled');

  const BookingStatus(this.value, this.label);

  final String value;
  final String label;

  static BookingStatus fromValue(String? value) {
    for (final status in values) {
      if (status.value == value) return status;
    }
    return BookingStatus.pending;
  }

  /// Not started yet (customers may still cancel or reschedule, in time).
  bool get isUpcoming =>
      this == pending || this == confirmed || this == providerAssigned;

  /// The professional is on the way or at work.
  bool get isActive => this == onTheWay || this == inProgress;
}

/// The tabs on the Bookings screen.
enum BookingTab {
  upcoming('Upcoming'),
  active('Active'),
  completed('Completed'),
  cancelled('Cancelled');

  const BookingTab(this.label);

  final String label;

  static BookingTab of(BookingStatus status) {
    if (status.isUpcoming) return upcoming;
    if (status.isActive) return active;
    return status == BookingStatus.completed ? completed : cancelled;
  }
}

/// A customer's booking (`public.bookings`).
class Booking {
  const Booking({
    required this.id,
    required this.reference,
    required this.serviceId,
    required this.serviceName,
    required this.bookingType,
    required this.startsAt,
    required this.endsAt,
    required this.emirate,
    required this.area,
    required this.building,
    required this.customerName,
    required this.customerPhone,
    required this.status,
    required this.createdAt,
    this.hours,
    this.apartment = '',
    this.addressNotes = '',
    this.instructions = '',
    this.priceEstimate,
    this.priceUnit,
    this.paymentMethod = PaymentMethod.cash,
    this.staffName,
    this.staffYearsExperience,
    this.cancelReason = '',
  });

  factory Booking.fromJson(Map<String, dynamic> json) {
    final staff = json['service_staff'] as Map<String, dynamic>?;
    final payment = json['payment_method'] as String?;
    return Booking(
      id: json['id'] as String,
      reference: json['reference'] as String,
      serviceId: json['service_id'] as String,
      serviceName: json['service_name'] as String,
      bookingType: BookingType.fromValue(json['booking_type'] as String?),
      hours: json['hours'] as int?,
      startsAt: DateTime.parse(json['starts_at'] as String),
      endsAt: DateTime.parse(json['ends_at'] as String),
      emirate: json['emirate'] as String,
      area: json['area'] as String,
      building: json['building'] as String,
      apartment: json['apartment'] as String? ?? '',
      addressNotes: json['address_notes'] as String? ?? '',
      instructions: json['instructions'] as String? ?? '',
      customerName: json['customer_name'] as String,
      customerPhone: json['customer_phone'] as String,
      priceEstimate: (json['price_estimate'] as num?)?.toDouble(),
      priceUnit: PriceUnit.fromValue(json['price_unit'] as String?),
      paymentMethod: PaymentMethod.values.firstWhere(
        (method) => method.value == payment,
        orElse: () => PaymentMethod.cash,
      ),
      status: BookingStatus.fromValue(json['status'] as String?),
      staffName: staff?['display_name'] as String?,
      staffYearsExperience: staff?['years_experience'] as int?,
      cancelReason: json['cancel_reason'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Customers see only the staff assigned to their own bookings.
  static const String columns =
      'id, reference, service_id, service_name, booking_type, hours, '
      'starts_at, ends_at, emirate, area, building, apartment, address_notes, '
      'instructions, customer_name, customer_phone, price_estimate, '
      'price_unit, payment_method, status, cancel_reason, created_at, '
      'service_staff(display_name, years_experience)';

  final String id;
  final String reference;
  final String serviceId;
  final String serviceName;
  final BookingType bookingType;
  final int? hours;
  final DateTime startsAt;
  final DateTime endsAt;
  final String emirate;
  final String area;
  final String building;
  final String apartment;
  final String addressNotes;
  final String instructions;
  final String customerName;
  final String customerPhone;

  /// Null = the price is confirmed by the agency.
  final double? priceEstimate;
  final PriceUnit? priceUnit;
  final PaymentMethod paymentMethod;
  final BookingStatus status;

  /// The assigned professional, e.g. "Grace K." (null until assigned).
  final String? staffName;
  final int? staffYearsExperience;
  final String cancelReason;
  final DateTime createdAt;

  BookingTab get tab => BookingTab.of(status);

  /// "1204, Tower 1, JLT, Dubai"
  String get address => [
    if (apartment.isNotEmpty) apartment,
    building,
    area,
    emirate,
  ].join(', ');

  /// The last moment the customer can cancel or reschedule in the app.
  DateTime changeDeadline(BookingSettings settings) =>
      startsAt.subtract(Duration(hours: settings.cancelHours));

  /// The database applies the same rule.
  bool canChange(BookingSettings settings, [DateTime? now]) =>
      status.isUpcoming &&
      (now ?? DateTime.now()).isBefore(changeDeadline(settings));
}

/// One step in a booking's timeline (`public.booking_history`).
class BookingEvent {
  const BookingEvent({
    required this.status,
    required this.createdAt,
    this.note = '',
  });

  factory BookingEvent.fromJson(Map<String, dynamic> json) {
    return BookingEvent(
      status: BookingStatus.fromValue(json['status'] as String?),
      note: json['note'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final BookingStatus status;
  final String note;
  final DateTime createdAt;
}
