import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/phone_number.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../data/auth_providers.dart';
import '../domain/auth_repository.dart';
import 'verify_code_args.dart';
import 'widgets/auth_scaffold.dart';

/// Enter the 6-digit code sent by WhatsApp, SMS or email.
class VerifyCodeScreen extends ConsumerStatefulWidget {
  const VerifyCodeScreen({super.key, required this.args});

  final VerifyCodeArgs args;

  /// Seconds before a new code can be requested.
  static const int resendDelaySeconds = 60;

  @override
  ConsumerState<VerifyCodeScreen> createState() => _VerifyCodeScreenState();
}

class _VerifyCodeScreenState extends ConsumerState<VerifyCodeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  Timer? _timer;
  int _secondsLeft = VerifyCodeScreen.resendDelaySeconds;
  bool _verifying = false;

  VerifyCodeArgs get _args => widget.args;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _code.dispose();
    super.dispose();
  }

  void _startCountdown() {
    _timer?.cancel();
    setState(() => _secondsLeft = VerifyCodeScreen.resendDelaySeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_secondsLeft <= 1) timer.cancel();
      setState(() => _secondsLeft -= 1);
    });
  }

  String get _sentToText {
    switch (_args.purpose) {
      case VerifyCodePurpose.phoneSignIn:
      case VerifyCodePurpose.phoneSignUp:
        return 'We sent a 6-digit code to ${PhoneNumbers.mask(_args.destination)}.';
      case VerifyCodePurpose.emailSignUp:
      case VerifyCodePurpose.passwordReset:
        return 'We sent a 6-digit code to ${_args.destination}. '
            'Check your inbox and spam folder.';
    }
  }

  Future<void> _verify() async {
    if (_verifying) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final code = _code.text.trim();
    final auth = ref.read(authRepositoryProvider);

    setState(() => _verifying = true);
    try {
      switch (_args.purpose) {
        case VerifyCodePurpose.phoneSignIn:
        case VerifyCodePurpose.phoneSignUp:
          await auth.verifyPhoneCode(phone: _args.destination, code: code);
        case VerifyCodePurpose.emailSignUp:
          await auth.verifyEmailSignUpCode(
            email: _args.destination,
            code: code,
          );
        case VerifyCodePurpose.passwordReset:
          await auth.verifyPasswordResetCode(
            email: _args.destination,
            code: code,
          );
      }
      if (!mounted) return;
      context.go(
        _args.purpose == VerifyCodePurpose.passwordReset
            ? AppRoutes.newPassword
            : AppRoutes.home,
      );
    } on AppFailure catch (failure) {
      if (!mounted) return;
      _code.clear();
      showErrorSnackBar(context, failure);
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _resend({
    PhoneCodeChannel channel = PhoneCodeChannel.whatsapp,
  }) async {
    final auth = ref.read(authRepositoryProvider);
    try {
      switch (_args.purpose) {
        case VerifyCodePurpose.phoneSignIn:
        case VerifyCodePurpose.phoneSignUp:
          await auth.sendPhoneCode(
            phone: _args.destination,
            channel: channel,
            createUser: _args.purpose == VerifyCodePurpose.phoneSignUp,
            fullName: _args.fullName,
          );
        case VerifyCodePurpose.emailSignUp:
          await auth.resendEmailSignUpCode(_args.destination);
        case VerifyCodePurpose.passwordReset:
          await auth.sendPasswordResetCode(_args.destination);
      }
      if (!mounted) return;
      _startCountdown();
      showAppSnackBar(
        context,
        channel == PhoneCodeChannel.sms
            ? 'A new code has been sent by SMS.'
            : 'A new code has been sent.',
      );
    } on AppFailure catch (failure) {
      if (mounted) showErrorSnackBar(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canResend = _secondsLeft <= 0;
    final smsFallback =
        _args.isPhone &&
        (ref.watch(smsFallbackEnabledProvider).value ?? false);

    return AuthScaffold(
      title: 'Enter verification code',
      subtitle: _sentToText,
      children: [
        Form(
          key: _formKey,
          child: TextFormField(
            controller: _code,
            autofocus: true,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            textAlign: TextAlign.center,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            style: AppTypography.headlineMedium.copyWith(letterSpacing: 12),
            decoration: const InputDecoration(
              hintText: '••••••',
              semanticCounterText: '6-digit code',
            ),
            autovalidateMode: AutovalidateMode.onUserInteractionIfError,
            validator: Validators.code,
            onChanged: (value) {
              if (value.length == 6) unawaited(_verify());
            },
            onFieldSubmitted: (_) => unawaited(_verify()),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppButton(label: 'Verify', isLoading: _verifying, onPressed: _verify),
        const SizedBox(height: AppSpacing.lg),
        Center(
          child: canResend
              ? AppButton(
                  label: 'Resend code',
                  variant: AppButtonVariant.text,
                  expand: false,
                  onPressed: _resend,
                )
              : Text(
                  'Resend code in 0:${_secondsLeft.toString().padLeft(2, '0')}',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
        ),
        if (smsFallback && canResend)
          Center(
            child: AppButton(
              label: 'Send by SMS instead',
              variant: AppButtonVariant.text,
              expand: false,
              onPressed: () => _resend(channel: PhoneCodeChannel.sms),
            ),
          ),
      ],
    );
  }
}
