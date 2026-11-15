/// The signed-in user, independent of the backend SDK.
class AppUser {
  const AppUser({required this.id, this.email, this.phone, this.fullName});

  final String id;
  final String? email;
  final String? phone;
  final String? fullName;
}

/// How a phone verification code is delivered.
enum PhoneCodeChannel { whatsapp, sms }

enum EmailSignUpResult {
  /// A 6-digit confirmation code was emailed.
  codeSent,

  /// Email confirmation is switched off; the user is already signed in.
  signedIn,
}

/// Authentication operations. All methods throw an `AppFailure` on error.
abstract interface class AuthRepository {
  AppUser? get currentUser;

  /// Emits the current user (or `null`) whenever the session changes.
  Stream<AppUser?> authStateChanges();

  /// Sends a 6-digit code to [phone] (E.164).
  ///
  /// With [createUser] false, fails if no account exists for the number.
  Future<void> sendPhoneCode({
    required String phone,
    required PhoneCodeChannel channel,
    required bool createUser,
    String? fullName,
  });

  Future<void> verifyPhoneCode({required String phone, required String code});

  Future<EmailSignUpResult> signUpWithEmail({
    required String fullName,
    required String email,
    required String password,
  });

  Future<void> verifyEmailSignUpCode({
    required String email,
    required String code,
  });

  Future<void> resendEmailSignUpCode(String email);

  Future<void> signInWithEmail({
    required String email,
    required String password,
  });

  Future<void> sendPasswordResetCode(String email);

  /// Verifies the reset code and signs the user in so they can set a new
  /// password with [updatePassword].
  Future<void> verifyPasswordResetCode({
    required String email,
    required String code,
  });

  Future<void> updatePassword(String newPassword);

  Future<void> signOut();
}
