import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_logo.dart';

/// Entry point for signed-out users: create an account, sign in, or browse
/// as a guest.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: DecoratedBox(
          decoration: const BoxDecoration(gradient: AppColors.backgroundWash),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - AppSpacing.xl * 2,
                  ),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Spacer(),
                        const Center(child: AppLogo.icon(size: 88)),
                        const SizedBox(height: AppSpacing.xl),
                        const Text(
                          'Welcome to ${AppConstants.appName}',
                          style: AppTypography.headlineLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Trusted domestic workers and home services, '
                          'all in one place.',
                          style: AppTypography.bodyLarge.copyWith(
                            color: AppColors.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const Spacer(flex: 2),
                        AppButton(
                          label: 'Create Account',
                          onPressed: () => unawaited(context.push(AppRoutes.signUp)),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        AppButton(
                          label: 'Sign In',
                          variant: AppButtonVariant.outline,
                          onPressed: () => unawaited(context.push(AppRoutes.signIn)),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        AppButton(
                          label: 'Continue as guest',
                          variant: AppButtonVariant.text,
                          onPressed: () => context.go(AppRoutes.home),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
