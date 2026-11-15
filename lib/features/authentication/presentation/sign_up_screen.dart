import 'dart:async';

import 'package:flutter/material.dart';
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
import '../../../core/widgets/app_text_field.dart';
import '../data/auth_providers.dart';
import '../domain/auth_repository.dart';
import 'verify_code_args.dart';
import 'widgets/auth_method_switch.dart';
import 'widgets/auth_scaffold.dart';
import 'widgets/phone_field.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _phoneFormKey = GlobalKey<FormState>();
  final _emailFormKey = GlobalKey<FormState>();
  final _phoneName = TextEditingController();
  final _phone = TextEditingController();
  final _emailName = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  AuthMethod _method = AuthMethod.whatsapp;
  GccCountry _country = GccCountries.uae;

  @override
  void dispose() {
    for (final controller in [
      _phoneName,
      _phone,
      _emailName,
      _email,
      _password,
      _confirmPassword,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _signUpWithPhone() async {
    if (!(_phoneFormKey.currentState?.validate() ?? false)) return;
    final phone = PhoneNumbers.toE164(_phone.text, _country)!;
    final fullName = _phoneName.text.trim();
    try {
      await ref
          .read(authRepositoryProvider)
          .sendPhoneCode(
            phone: phone,
            channel: PhoneCodeChannel.whatsapp,
            createUser: true,
            fullName: fullName,
          );
      if (!mounted) return;
      unawaited(
        context.push(
          AppRoutes.verifyCode,
          extra: VerifyCodeArgs(
            purpose: VerifyCodePurpose.phoneSignUp,
            destination: phone,
            fullName: fullName,
          ),
        ),
      );
    } on AppFailure catch (failure) {
      if (mounted) showErrorSnackBar(context, failure);
    }
  }

  Future<void> _signUpWithEmail() async {
    if (!(_emailFormKey.currentState?.validate() ?? false)) return;
    final email = _email.text.trim();
    try {
      final result = await ref
          .read(authRepositoryProvider)
          .signUpWithEmail(
            fullName: _emailName.text.trim(),
            email: email,
            password: _password.text,
          );
      if (!mounted) return;
      switch (result) {
        case EmailSignUpResult.signedIn:
          context.go(AppRoutes.home);
        case EmailSignUpResult.codeSent:
          unawaited(
            context.push(
              AppRoutes.verifyCode,
              extra: VerifyCodeArgs(
                purpose: VerifyCodePurpose.emailSignUp,
                destination: email,
              ),
            ),
          );
      }
    } on AppFailure catch (failure) {
      if (mounted) showErrorSnackBar(context, failure);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Create your account',
      subtitle: 'Book home services and hire trusted domestic workers.',
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
                AppTextField(
                  controller: _phoneName,
                  label: 'Full name',
                  prefixIcon: Icons.person_outline_rounded,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.name],
                  validator: Validators.fullName,
                ),
                const SizedBox(height: AppSpacing.md),
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
                  onPressed: _signUpWithPhone,
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
                    controller: _emailName,
                    label: 'Full name',
                    prefixIcon: Icons.person_outline_rounded,
                    textInputAction: TextInputAction.next,
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.name],
                    validator: Validators.fullName,
                  ),
                  const SizedBox(height: AppSpacing.md),
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
                    hint: 'At least 8 characters, letters and numbers',
                    prefixIcon: Icons.lock_outline_rounded,
                    obscureText: true,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.newPassword],
                    validator: Validators.newPassword,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  AppTextField(
                    controller: _confirmPassword,
                    label: 'Confirm password',
                    prefixIcon: Icons.lock_outline_rounded,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    validator: Validators.confirmPassword(
                      () => _password.text,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  AppButton(
                    label: 'Create Account',
                    onPressed: _signUpWithEmail,
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.md),
        const Text(
          'By creating an account you agree to our Terms and Conditions and '
          'Privacy Policy.',
          style: AppTypography.bodySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Already have an account?',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            TextButton(
              onPressed: () => context.pushReplacement(AppRoutes.signIn),
              child: const Text('Sign in'),
            ),
          ],
        ),
      ],
    );
  }
}
