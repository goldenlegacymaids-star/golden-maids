/// Why a verification code is being entered.
enum VerifyCodePurpose { phoneSignIn, phoneSignUp, emailSignUp, passwordReset }

/// Passed to the verification screen through the router.
class VerifyCodeArgs {
  const VerifyCodeArgs({
    required this.purpose,
    required this.destination,
    this.fullName,
  });

  final VerifyCodePurpose purpose;

  /// E.164 phone number or email address the code was sent to.
  final String destination;

  /// Name given at phone sign-up (needed to resend the code).
  final String? fullName;

  bool get isPhone =>
      purpose == VerifyCodePurpose.phoneSignIn ||
      purpose == VerifyCodePurpose.phoneSignUp;
}
