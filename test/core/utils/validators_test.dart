import 'package:flutter_test/flutter_test.dart';
import 'package:golden_maids/core/utils/validators.dart';

void main() {
  test('fullName', () {
    expect(Validators.fullName('Sarah Khan'), isNull);
    expect(Validators.fullName('  '), isNotNull);
    expect(Validators.fullName('S'), isNotNull);
    expect(Validators.fullName('x' * 121), isNotNull);
  });

  test('email', () {
    expect(Validators.email('sarah@example.com'), isNull);
    expect(Validators.email(' sarah@example.ae '), isNull);
    expect(Validators.email('sarah@'), isNotNull);
    expect(Validators.email('sarah example.com'), isNotNull);
    expect(Validators.email(''), isNotNull);
  });

  test('newPassword enforces length, letters and numbers', () {
    expect(Validators.newPassword('Secret123'), isNull);
    expect(Validators.newPassword('Sec1'), 'Use at least 8 characters');
    expect(Validators.newPassword('password'), 'Use both letters and numbers');
    expect(Validators.newPassword('12345678'), 'Use both letters and numbers');
  });

  test('confirmPassword compares with the original', () {
    final validator = Validators.confirmPassword(() => 'Secret123');
    expect(validator('Secret123'), isNull);
    expect(validator('Secret124'), 'Passwords do not match');
    expect(validator(''), isNotNull);
  });

  test('code requires exactly 6 digits', () {
    expect(Validators.code('123456'), isNull);
    expect(Validators.code('12345'), isNotNull);
    expect(Validators.code('12345a'), isNotNull);
  });
}
