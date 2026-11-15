import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/env.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../core/widgets/tab_screen.dart';
import '../../authentication/data/auth_providers.dart';
import '../../profile/data/profile_repository.dart';

/// Home tab. The full home screen (search, banners, categories, featured
/// maids) is built in Step 1.7.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user =
        ref.watch(authStateProvider).value ??
        ref.watch(authRepositoryProvider).currentUser;
    final profile = ref.watch(myProfileProvider).value;
    final name = profile?.firstName ?? user?.fullName?.split(' ').first;

    return TabScreen(
      title: user == null ? 'Hello, guest' : 'Hello, ${name ?? 'there'}',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              user == null
                  ? "You're browsing as a guest. Sign in to book services "
                        'or hire domestic workers.'
                  : 'What services do you want to use today?',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const AppCard(
              child: Row(
                children: [
                  AppLogo.icon(size: 48),
                  SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      'Search, offers, service categories and featured '
                      'maids arrive here in Step 1.7.',
                      style: AppTypography.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
            if (user == null) ...[
              const SizedBox(height: AppSpacing.xl),
              AppButton(
                label: 'Sign In',
                onPressed: () => unawaited(context.push(AppRoutes.signIn)),
              ),
            ],
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
    );
  }
}
