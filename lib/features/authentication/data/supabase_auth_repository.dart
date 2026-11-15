import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/errors/app_failure.dart';
import '../domain/auth_repository.dart';

/// [AuthRepository] backed by Supabase Auth.
class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._auth);

  final GoTrueClient _auth;

  static AppUser? _toAppUser(User? user) {
    if (user == null) return null;
    final name = user.userMetadata?['full_name'];
    return AppUser(
      id: user.id,
      email: user.email,
      phone: user.phone,
      fullName: name is String ? name : null,
    );
  }

  /// Runs [action] and converts any error into an [AppFailure].
  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(AppFailure.from(error), stackTrace);
    }
  }

  @override
  AppUser? get currentUser => _toAppUser(_auth.currentUser);

  @override
  Stream<AppUser?> authStateChanges() {
    return _auth.onAuthStateChange.map(
      (state) => _toAppUser(state.session?.user),
    );
  }

  @override
  Future<void> sendPhoneCode({
    required String phone,
    required PhoneCodeChannel channel,
    required bool createUser,
    String? fullName,
  }) {
    return _guard(
      () => _auth.signInWithOtp(
        phone: phone,
        shouldCreateUser: createUser,
        channel: switch (channel) {
          PhoneCodeChannel.whatsapp => OtpChannel.whatsapp,
          PhoneCodeChannel.sms => OtpChannel.sms,
        },
        data: fullName == null ? null : {'full_name': fullName},
      ),
    );
  }

  @override
  Future<void> verifyPhoneCode({required String phone, required String code}) {
    return _guard(
      () => _auth.verifyOTP(phone: phone, token: code, type: OtpType.sms),
    );
  }

  @override
  Future<EmailSignUpResult> signUpWithEmail({
    required String fullName,
    required String email,
    required String password,
  }) {
    return _guard(() async {
      final response = await _auth.signUp(
        email: email,
        password: password,
        data: {'full_name': fullName},
      );
      if (response.session != null) return EmailSignUpResult.signedIn;

      // Supabase returns a user without identities when the email is
      // already registered (no email is sent in that case).
      final identities = response.user?.identities;
      if (identities != null && identities.isEmpty) {
        throw const ValidationFailure(
          message: 'An account with this email already exists. '
              'Please sign in.',
        );
      }
      return EmailSignUpResult.codeSent;
    });
  }

  @override
  Future<void> verifyEmailSignUpCode({
    required String email,
    required String code,
  }) {
    return _guard(
      () => _auth.verifyOTP(email: email, token: code, type: OtpType.email),
    );
  }

  @override
  Future<void> resendEmailSignUpCode(String email) {
    return _guard(() => _auth.resend(email: email, type: OtpType.signup));
  }

  @override
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) {
    return _guard(
      () => _auth.signInWithPassword(email: email, password: password),
    );
  }

  @override
  Future<void> sendPasswordResetCode(String email) {
    return _guard(() => _auth.resetPasswordForEmail(email));
  }

  @override
  Future<void> verifyPasswordResetCode({
    required String email,
    required String code,
  }) {
    return _guard(
      () => _auth.verifyOTP(email: email, token: code, type: OtpType.recovery),
    );
  }

  @override
  Future<void> updatePassword(String newPassword) {
    return _guard(() => _auth.updateUser(UserAttributes(password: newPassword)));
  }

  @override
  Future<void> signOut() => _guard(_auth.signOut);
}

/// Used when the app has no Supabase settings (e.g. UI work without
/// env.json). Nobody is signed in and every action reports the problem.
class UnavailableAuthRepository implements AuthRepository {
  const UnavailableAuthRepository();

  static const _failure = ServerFailure(
    message: 'Sign-in is not available: the app is not connected to its '
        'server.',
  );

  @override
  AppUser? get currentUser => null;

  @override
  Stream<AppUser?> authStateChanges() => Stream<AppUser?>.value(null);

  @override
  Future<void> sendPhoneCode({
    required String phone,
    required PhoneCodeChannel channel,
    required bool createUser,
    String? fullName,
  }) => Future.error(_failure);

  @override
  Future<void> verifyPhoneCode({required String phone, required String code}) =>
      Future.error(_failure);

  @override
  Future<EmailSignUpResult> signUpWithEmail({
    required String fullName,
    required String email,
    required String password,
  }) => Future.error(_failure);

  @override
  Future<void> verifyEmailSignUpCode({
    required String email,
    required String code,
  }) => Future.error(_failure);

  @override
  Future<void> resendEmailSignUpCode(String email) => Future.error(_failure);

  @override
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) => Future.error(_failure);

  @override
  Future<void> sendPasswordResetCode(String email) => Future.error(_failure);

  @override
  Future<void> verifyPasswordResetCode({
    required String email,
    required String code,
  }) => Future.error(_failure);

  @override
  Future<void> updatePassword(String newPassword) => Future.error(_failure);

  @override
  Future<void> signOut() async {}
}
