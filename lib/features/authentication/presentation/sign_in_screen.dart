import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../../../core/errors/app_failure.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/phone_number.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/app_text_field.dart';
import '../data/auth_providers.dart';
import '../domain/auth_repository.dart';
import 'verify_code_args.dart';
import 'widgets/auth_method_switch.dart';
import 'widgets/auth_scaffold.dart';
import 'widgets/phone_field.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _phoneFormKey = GlobalKey<FormState>();
  final _emailFormKey = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();

  AuthMethod _method = AuthMethod.whatsapp;
  GccCountry _country = GccCountries.uae;

  @override
  void dispose() {
    _phone.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _sendPhoneCode() async {
    if (!(_phoneFormKey.currentState?.validate() ?? false)) return;
    final phone = PhoneNumbers.toE164(_phone.text, _country)!;
    try {
      await ref
          .read(authRepositoryProvider)
          .sendPhoneCode(
            phone: phone,
            channel: PhoneCodeChannel.whatsapp,
            createUser: false,
          );
      if (!mounted) return;
      unawaited(
        context.push(
          AppRoutes.verifyCode,
          extra: VerifyCodeArgs(
            purpose: VerifyCodePurpose.phoneSignIn,
            destination: phone,
          ),
        ),
      );
    } on AppFailure catch (failure) {
      if (mounted) showErrorSnackBar(context, failure);
    }
  }

  Future<void> _signInWithEmail() async {
    if (!(_emailFormKey.currentState?.validate() ?? false)) return;
    final email = _email.text.trim();
    final auth = ref.read(authRepositoryProvider);
    try {
      await auth.signInWithEmail(email: email, password: _password.text);
      if (mounted) context.go(AppRoutes.home);
    } on AppFailure catch (failure) {
      if (!mounted) return;
      final cause = failure.cause;
      if (cause is AuthException && cause.code == 'email_not_confirmed') {
        // The account exists but the email was never confirmed: send a new
        // code and continue to verification.
        showErrorSnackBar(context, failure);
        try {
          await auth.resendEmailSignUpCode(email);
        } on AppFailure catch (resendFailure) {
          if (mounted) showErrorSnackBar(context, resendFailure);
          return;
        }
        if (!mounted) return;
        unawaited(
          context.push(
            AppRoutes.verifyCode,
            extra: VerifyCodeArgs(
              purpose: VerifyCodePurpose.emailSignUp,
              destination: email,
            ),
          ),
        );
        return;
      }
      showErrorSnackBar(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Welcome back',
      subtitle: 'Sign in to manage your hiring requests.',
      children: [
        AuthMethodSwitch(
          value: _method,
          onChanged: (method) => setState(() => _method = method),
        ),
        const SizedBox(height: AppSpacing.xl),
        if (_method == AuthMethod.whatsapp)
          Form(
            key: _phoneFormKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PhoneField(
                  controller: _phone,
                  country: _country,
                  onCountryChanged: (country) =>
                      setState(() => _country = country),
                  textInputAction: TextInputAction.done,
                ),
                const SizedBox(height: AppSpacing.xs),
                const Text(
                  "We'll send a 6-digit code to this number on WhatsApp.",
                  style: AppTypography.bodySmall,
                ),
                const SizedBox(height: AppSpacing.xl),
                AppButton(
                  label: 'Send code via WhatsApp',
                  onPressed: _sendPhoneCode,
                ),
              ],
            ),
          )
        else
          Form(
            key: _emailFormKey,
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppTextField(
                    controller: _email,
                    label: 'Email address',
                    prefixIcon: Icons.mail_outline_rounded,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                    validator: Validators.email,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    controller: _password,
                    label: 'Password',
                    prefixIcon: Icons.lock_outline_rounded,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    validator: Validators.password,
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => context.push(AppRoutes.forgotPassword),
                      child: const Text('Forgot password?'),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppButton(label: 'Sign In', onPressed: _signInWithEmail),
                ],
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.xl),
        // Wrap (not Row) so the link moves to a new line on small screens
        // or with large accessibility text sizes.
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              "Don't have an account?",
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            TextButton(
              onPressed: () => context.pushReplacement(AppRoutes.signUp),
              child: const Text('Create one'),
            ),
          ],
        ),
      ],
    );
  }
}
