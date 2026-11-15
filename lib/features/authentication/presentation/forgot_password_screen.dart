import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/app_text_field.dart';
import '../data/auth_providers.dart';
import 'verify_code_args.dart';
import 'widgets/auth_scaffold.dart';

/// Request a password-reset code for an email account.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final email = _email.text.trim();
    try {
      await ref.read(authRepositoryProvider).sendPasswordResetCode(email);
      if (!mounted) return;
      unawaited(
        context.push(
          AppRoutes.verifyCode,
          extra: VerifyCodeArgs(
            purpose: VerifyCodePurpose.passwordReset,
            destination: email,
          ),
        ),
      );
    } on AppFailure catch (failure) {
      if (mounted) showErrorSnackBar(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Forgot password?',
      subtitle:
          "Enter your account's email address. If an account exists, we'll "
          'send you a 6-digit code to reset your password.',
      children: [
        Form(
          key: _formKey,
          child: AppTextField(
            controller: _email,
            label: 'Email address',
            prefixIcon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.email],
            validator: Validators.email,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppButton(label: 'Send reset code', onPressed: _sendCode),
      ],
    );
  }
}
