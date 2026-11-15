/// Form validators. Each returns an error message, or `null` when valid.
abstract final class Validators {
  static final RegExp _email = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$');
  static final RegExp _letter = RegExp('[A-Za-z]');
  static final RegExp _digit = RegExp(r'\d');
  static final RegExp _code = RegExp(r'^\d{6}$');

  static const int minPasswordLength = 8;

  static String? fullName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Please enter your full name';
    if (name.length < 2) return 'Name is too short';
    if (name.length > 120) return 'Name is too long';
    return null;
  }

  static String? email(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Please enter your email address';
    if (!_email.hasMatch(email)) return 'Please enter a valid email address';
    return null;
  }

  /// For creating a password: enforces the password policy.
  static String? newPassword(String? value) {
    final password = value ?? '';
    if (password.isEmpty) return 'Please enter a password';
    if (password.length < minPasswordLength) {
      return 'Use at least $minPasswordLength characters';
    }
    if (!_letter.hasMatch(password) || !_digit.hasMatch(password)) {
      return 'Use both letters and numbers';
    }
    return null;
  }

  /// For signing in: only checks that something was entered.
  static String? password(String? value) {
    if ((value ?? '').isEmpty) return 'Please enter your password';
    return null;
  }

  static String? Function(String?) confirmPassword(String Function() original) {
    return (value) {
      if ((value ?? '').isEmpty) return 'Please confirm your password';
      if (value != original()) return 'Passwords do not match';
      return null;
    };
  }

  static String? code(String? value) {
    if (!_code.hasMatch(value?.trim() ?? '')) {
      return 'Enter the 6-digit code';
    }
    return null;
  }
}
