import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/env.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../authentication/data/auth_providers.dart';
import '../../profile/data/profile_repository.dart';

/// TEMPORARY home screen to test sign-in, guest browsing and sign-out.
/// Replaced by the real app shell and home screen in Steps 1.6–1.7.
class TemporaryHomeScreen extends ConsumerWidget {
  const TemporaryHomeScreen({super.key});

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(authRepositoryProvider).signOut();
      if (context.mounted) context.go(AppRoutes.welcome);
    } on AppFailure catch (failure) {
      if (context.mounted) showErrorSnackBar(context, failure);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user =
        ref.watch(authStateProvider).value ??
        ref.watch(authRepositoryProvider).currentUser;
    final profile = ref.watch(myProfileProvider).value;

    final name = profile?.firstName ?? user?.fullName?.split(' ').first;
    final contact = profile?.email ?? profile?.phone ?? user?.email ?? user?.phone;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: DecoratedBox(
          decoration: const BoxDecoration(gradient: AppColors.backgroundWash),
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.xl),
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: AppLogo.full(height: 44),
                ),
                const SizedBox(height: AppSpacing.xxl),
                Text(
                  user == null
                      ? 'Hello, guest'
                      : 'Hello, ${name ?? 'there'}',
                  style: AppTypography.headlineLarge,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  user == null
                      ? "You're browsing as a guest. Sign in to book services "
                            'or hire domestic workers.'
                      : 'You are signed in${contact == null ? '' : ' as $contact'}.',
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                const AppCard(
                  child: Text(
                    'The home screen, services and bottom navigation arrive '
                    'in Steps 1.6 and 1.7.',
                    style: AppTypography.bodyMedium,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                if (user == null) ...[
                  AppButton(
                    label: 'Sign In',
                    onPressed: () => unawaited(context.push(AppRoutes.signIn)),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppButton(
                    label: 'Create Account',
                    variant: AppButtonVariant.outline,
                    onPressed: () => unawaited(context.push(AppRoutes.signUp)),
                  ),
                ] else
                  AppButton(
                    label: 'Log Out',
                    icon: Icons.logout_rounded,
                    variant: AppButtonVariant.outline,
                    onPressed: () => _signOut(context, ref),
                  ),
                if (!Env.isProduction) ...[
                  const SizedBox(height: AppSpacing.md),
                  AppButton(
                    label: 'Design preview (development only)',
                    variant: AppButtonVariant.text,
                    onPressed: () =>
                        unawaited(context.push(AppRoutes.designPreview)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
