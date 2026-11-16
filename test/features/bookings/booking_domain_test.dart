import 'package:flutter_test/flutter_test.dart';
import 'package:golden_maids/features/bookings/domain/booking.dart';
import 'package:golden_maids/features/services/domain/catalog.dart';

HomeService _service({
  BookingType type = BookingType.hourly,
  double? price = 45,
  PriceUnit? unit = PriceUnit.perHour,
  int? duration,
}) => HomeService(
  id: 's',
  categoryId: 'c',
  slug: 's',
  name: 'Service',
  basePrice: price,
  priceUnit: unit,
  durationMinutes: duration,
  bookingType: type,
);

void main() {
  group('BookingSettings', () {
    test('reads the database row', () {
      final settings = BookingSettings.fromJson({
        'open_time': '08:00:00',
        'close_time': '20:30:00',
        'open_days': [1, 2, 3, 4, 5, 6],
        'slot_minutes': 30,
        'min_hours': 3,
        'max_hours': 6,
        'min_notice_hours': 4,
        'window_days': 14,
        'cancel_hours': 12,
        'default_visit_minutes': 180,
      });
      expect(settings.openMinutes, 480);
      expect(settings.closeMinutes, 1230);
      expect(settings.slotMinutes, 30);
      expect(settings.minHours, 3);
      expect(settings.maxHours, 6);
      expect(settings.cancelHours, 12);
      expect(settings.defaultVisitMinutes, 180);
      // ISO weekdays, like DateTime.weekday: Sunday (7) is closed.
      expect(settings.isOpenOn(DateTime(2026, 11, 22)), isFalse);
      expect(settings.isOpenOn(DateTime(2026, 11, 23)), isTrue);
    });

    test('bookable days run from the UAE date for the window', () {
      const settings = BookingSettings(windowDays: 2);
      // 22:30 UTC on 16 Nov is 02:30 on 17 Nov in the UAE.
      final days = settings.bookableDays(DateTime.utc(2026, 11, 16, 22, 30));
      expect(days, [
        DateTime(2026, 11, 17),
        DateTime(2026, 11, 18),
        DateTime(2026, 11, 19),
      ]);
    });
  });

  test('UAE time and dates', () {
    final uae = toUae(DateTime.utc(2026, 11, 20, 5));
    expect((uae.hour, uae.day), (9, 20));
    expect(isoDate(DateTime(2026, 3, 7)), '2026-03-07');
  });

  test('slots are read from the database function', () {
    final slot = TimeSlot.fromJson({
      'starts_at': '2026-11-20T05:00:00+00:00',
      'is_available': true,
    });
    expect(slot.startsAt, DateTime.utc(2026, 11, 20, 5));
    expect(slot.isAvailable, isTrue);
  });

  group('price estimate (as the database computes it)', () {
    test('hourly per-hour price × hours', () {
      expect(priceEstimate(_service(), 3), 135);
    });
    test('visit price as listed', () {
      final visit = _service(
        type: BookingType.visit,
        price: 450,
        unit: PriceUnit.perVisit,
      );
      expect(priceEstimate(visit, null), 450);
    });
    test('no price: confirmed by the agency', () {
      expect(priceEstimate(_service(price: null), 2), isNull);
    });
  });

  test('job length', () {
    const settings = BookingSettings();
    expect(jobMinutes(_service(), settings, 3), 180);
    expect(
      jobMinutes(_service(type: BookingType.visit), settings, null),
      240,
    );
    expect(
      jobMinutes(_service(type: BookingType.visit, duration: 300), settings, 2),
      300,
    );
    expect(jobMinutes(_service(type: BookingType.request), settings, null), 60);
  });

  test('a booking is sent with the start time in UTC', () {
    final draft = BookingDraft(
      serviceId: 's3',
      hours: 2,
      startsAt: DateTime.utc(2026, 11, 20, 5),
      addressId: 'a1',
      address: const AddressInput(
        emirate: 'Dubai',
        area: 'JLT',
        building: 'Tower 1',
      ),
      customerName: 'Sarah Khan',
      customerPhone: '+971501234567',
      paymentMethod: PaymentMethod.cardOnCompletion,
    );
    final json = draft.toInsertJson();
    expect(json['starts_at'], '2026-11-20T05:00:00.000Z');
    expect(json['payment_method'], 'card_on_completion');
    expect(json['hours'], 2);
    expect(json['address_id'], 'a1');
    expect(json['apartment'], '');
    expect(json.containsKey('customer_id'), isFalse);
    expect(json.containsKey('price_estimate'), isFalse);
  });

  test('service booking type defaults to request', () {
    expect(BookingType.fromValue('visit'), BookingType.visit);
    expect(BookingType.fromValue(null), BookingType.request);
    expect(BookingType.fromValue('other'), BookingType.request);
  });
}
