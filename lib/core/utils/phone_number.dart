/// A GCC country for phone sign-in.
class GccCountry {
  const GccCountry({
    required this.isoCode,
    required this.name,
    required this.dialCode,
    required this.flag,
    required this.mobilePattern,
    required this.example,
  });

  final String isoCode;
  final String name;

  /// Without the plus sign, e.g. `971`.
  final String dialCode;

  final String flag;

  /// Valid national mobile numbers (without the leading 0).
  final String mobilePattern;

  /// Example shown as the input hint.
  final String example;

  @override
  String toString() => '$flag +$dialCode';
}

abstract final class GccCountries {
  static const GccCountry uae = GccCountry(
    isoCode: 'AE',
    name: 'United Arab Emirates',
    dialCode: '971',
    flag: '🇦🇪',
    mobilePattern: r'^5\d{8}$',
    example: '50 123 4567',
  );
  static const GccCountry saudiArabia = GccCountry(
    isoCode: 'SA',
    name: 'Saudi Arabia',
    dialCode: '966',
    flag: '🇸🇦',
    mobilePattern: r'^5\d{8}$',
    example: '50 123 4567',
  );
  static const GccCountry qatar = GccCountry(
    isoCode: 'QA',
    name: 'Qatar',
    dialCode: '974',
    flag: '🇶🇦',
    mobilePattern: r'^[3567]\d{7}$',
    example: '3312 3456',
  );
  static const GccCountry kuwait = GccCountry(
    isoCode: 'KW',
    name: 'Kuwait',
    dialCode: '965',
    flag: '🇰🇼',
    mobilePattern: r'^[4569]\d{7}$',
    example: '5012 3456',
  );
  static const GccCountry bahrain = GccCountry(
    isoCode: 'BH',
    name: 'Bahrain',
    dialCode: '973',
    flag: '🇧🇭',
    mobilePattern: r'^[36]\d{7}$',
    example: '3600 1234',
  );
  static const GccCountry oman = GccCountry(
    isoCode: 'OM',
    name: 'Oman',
    dialCode: '968',
    flag: '🇴🇲',
    mobilePattern: r'^[79]\d{7}$',
    example: '9212 3456',
  );

  static const List<GccCountry> all = [
    uae,
    saudiArabia,
    qatar,
    kuwait,
    bahrain,
    oman,
  ];
}

abstract final class PhoneNumbers {
  /// Converts what the user typed into international E.164 format
  /// (e.g. `+971501234567`), or returns `null` if it is not a valid mobile
  /// number for [country].
  ///
  /// Accepts spaces, dashes, a leading 0, or the number already including
  /// the country code (`+971…` or `00971…`).
  static String? toE164(String input, GccCountry country) {
    var digits = input.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('00')) digits = digits.substring(2);

    final pattern = RegExp(country.mobilePattern);
    final candidates = <String>[
      digits,
      if (digits.startsWith('0')) digits.substring(1),
      if (digits.startsWith(country.dialCode))
        digits.substring(country.dialCode.length),
      if (digits.startsWith('${country.dialCode}0'))
        digits.substring(country.dialCode.length + 1),
    ];

    for (final candidate in candidates) {
      if (pattern.hasMatch(candidate)) return '+${country.dialCode}$candidate';
    }
    return null;
  }

  /// Hides the middle digits for display, e.g. `+971 50 ••• 4567`.
  static String mask(String e164) {
    final digits = e164.replaceAll(RegExp(r'\D'), '');
    if (digits.length < 8) return e164;
    final country = GccCountries.all
        .where((c) => digits.startsWith(c.dialCode))
        .firstOrNull;
    final dial = country?.dialCode ?? digits.substring(0, 3);
    final national = digits.substring(dial.length);
    final start = national.substring(0, 2);
    final end = national.substring(national.length - 4);
    return '+$dial $start ••• $end';
  }
}
