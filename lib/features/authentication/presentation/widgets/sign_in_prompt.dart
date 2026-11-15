import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';

/// Shown to guests on screens that need an account.
class SignInPrompt extends StatelessWidget {
  const SignInPrompt({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.onBeforeNavigate,
  });

  final IconData icon;
  final String title;
  final String message;

  /// Called before opening Sign In / Create Account (e.g. to close a
  /// bottom sheet first).
  final VoidCallback? onBeforeNavigate;

  void _open(BuildContext context, String route) {
    final router = GoRouter.of(context);
    onBeforeNavigate?.call();
    unawaited(router.push(route));
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(
              color: AppColors.lightBlue,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 40, color: AppColors.primary),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            title,
            style: AppTypography.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            message,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xl),
          AppButton(
            label: 'Sign In',
            onPressed: () => _open(context, AppRoutes.signIn),
          ),
          const SizedBox(height: AppSpacing.sm),
          AppButton(
            label: 'Create Account',
            variant: AppButtonVariant.outline,
            onPressed: () => _open(context, AppRoutes.signUp),
          ),
        ],
      ),
    );
  }
}
