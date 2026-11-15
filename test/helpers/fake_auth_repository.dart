import 'dart:async';

import 'package:golden_maids/core/errors/app_failure.dart';
import 'package:golden_maids/features/authentication/domain/auth_repository.dart';

/// In-memory [AuthRepository] for widget tests.
///
/// The valid verification code is always [validCode].
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({AppUser? signedInUser}) : _user = signedInUser;

  static const String validCode = '123456';

  final _controller = StreamController<AppUser?>.broadcast();
  AppUser? _user;

  /// Registered email accounts: email → password.
  final Map<String, String> emailAccounts = {};

  /// Registered phone numbers.
  final Set<String> phoneAccounts = {};

  /// Every call made, e.g. `sendPhoneCode:+971501234567:whatsapp`.
  final List<String> calls = [];

  String? _pendingName;
  String? lastPasswordSet;

  void _signIn(AppUser user) {
    _user = user;
    _controller.add(user);
  }

  @override
  AppUser? get currentUser => _user;

  @override
  Stream<AppUser?> authStateChanges() async* {
    yield _user;
    yield* _controller.stream;
  }

  @override
  Future<void> sendPhoneCode({
    required String phone,
    required PhoneCodeChannel channel,
    required bool createUser,
    String? fullName,
  }) async {
    calls.add('sendPhoneCode:$phone:${channel.name}');
    if (!createUser && !phoneAccounts.contains(phone)) {
      throw const ValidationFailure(
        message: 'No account found with this number. '
            'Please create an account first.',
      );
    }
    _pendingName = fullName;
  }

  @override
  Future<void> verifyPhoneCode({
    required String phone,
    required String code,
  }) async {
    calls.add('verifyPhoneCode:$phone:$code');
    if (code != validCode) {
      throw const ValidationFailure(message: 'This code is incorrect.');
    }
    phoneAccounts.add(phone);
    _signIn(AppUser(id: 'phone-user', phone: phone, fullName: _pendingName));
  }

  @override
  Future<EmailSignUpResult> signUpWithEmail({
    required String fullName,
    required String email,
    required String password,
  }) async {
    calls.add('signUpWithEmail:$email');
    if (emailAccounts.containsKey(email)) {
      throw const ValidationFailure(message: 'Account already exists.');
    }
    emailAccounts[email] = password;
    _pendingName = fullName;
    return EmailSignUpResult.codeSent;
  }

  @override
  Future<void> verifyEmailSignUpCode({
    required String email,
    required String code,
  }) async {
    calls.add('verifyEmailSignUpCode:$email:$code');
    if (code != validCode) {
      throw const ValidationFailure(message: 'This code is incorrect.');
    }
    _signIn(AppUser(id: 'email-user', email: email, fullName: _pendingName));
  }

  @override
  Future<void> resendEmailSignUpCode(String email) async {
    calls.add('resendEmailSignUpCode:$email');
  }

  @override
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    calls.add('signInWithEmail:$email');
    if (emailAccounts[email] != password) {
      throw const ValidationFailure(message: 'Incorrect email or password.');
    }
    _signIn(AppUser(id: 'email-user', email: email, fullName: 'Sarah Khan'));
  }

  @override
  Future<void> sendPasswordResetCode(String email) async {
    calls.add('sendPasswordResetCode:$email');
  }

  @override
  Future<void> verifyPasswordResetCode({
    required String email,
    required String code,
  }) async {
    calls.add('verifyPasswordResetCode:$email:$code');
    if (code != validCode) {
      throw const ValidationFailure(message: 'This code is incorrect.');
    }
    _signIn(AppUser(id: 'email-user', email: email));
  }

  @override
  Future<void> updatePassword(String newPassword) async {
    calls.add('updatePassword');
    lastPasswordSet = newPassword;
  }

  @override
  Future<void> signOut() async {
    calls.add('signOut');
    _user = null;
    _controller.add(null);
  }

  Future<void> dispose() => _controller.close();
}
