import 'package:flutter_test/flutter_test.dart';
import 'package:golden_maids/core/utils/phone_number.dart';

void main() {
  group('PhoneNumbers.toE164 (UAE)', () {
    const uae = GccCountries.uae;

    test('accepts common ways of typing a UAE mobile number', () {
      for (final input in [
        '501234567',
        '0501234567',
        '050 123 4567',
        '050-123-4567',
        '+971501234567',
        '00971501234567',
        '971501234567',
        '+971 0501234567',
      ]) {
        expect(PhoneNumbers.toE164(input, uae), '+971501234567', reason: input);
      }
    });

    test('rejects numbers that are not UAE mobiles', () {
      for (final input in ['', '12345', '041234567', '50123456', '5012345678']) {
        expect(PhoneNumbers.toE164(input, uae), isNull, reason: input);
      }
    });
  });

  test('other GCC countries use their own format', () {
    expect(
      PhoneNumbers.toE164('3312 3456', GccCountries.qatar),
      '+97433123456',
    );
    expect(PhoneNumbers.toE164('0501234567', GccCountries.saudiArabia),
        '+966501234567');
    expect(PhoneNumbers.toE164('92123456', GccCountries.oman), '+96892123456');
    expect(PhoneNumbers.toE164('12345678', GccCountries.oman), isNull);
  });

  test('mask hides the middle digits', () {
    expect(PhoneNumbers.mask('+971501234567'), '+971 50 ••• 4567');
    expect(PhoneNumbers.mask('+97433123456'), '+974 33 ••• 3456');
  });
}
