import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/uae.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_icon_button.dart';
import '../../../authentication/data/auth_providers.dart';
import '../../../profile/data/profile_repository.dart';
import '../../data/service_location.dart';

/// Avatar, greeting, notifications and service location.
class HomeHeader extends ConsumerWidget {
  const HomeHeader({super.key});

  Future<void> _pickLocation(BuildContext context, WidgetRef ref) async {
    final current = ref.read(serviceLocationProvider);
    final selected = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  0,
                  AppSpacing.xl,
                  AppSpacing.xs,
                ),
                child: Text(
                  'Where do you need services?',
                  style: AppTypography.titleMedium,
                ),
              ),
              for (final emirate in UaeEmirates.all)
                ListTile(
                  leading: const Icon(Icons.location_on_rounded),
                  title: Text(emirate, style: AppTypography.bodyLarge),
                  trailing: emirate == current
                      ? const Icon(Icons.check_rounded, color: AppColors.primary)
                      : null,
                  selected: emirate == current,
                  onTap: () => Navigator.of(context).pop(emirate),
                ),
            ],
          ),
        ),
      ),
    );
    // The widget may have been removed while the sheet was open.
    if (selected == null || !context.mounted) return;
    await ref.read(serviceLocationProvider.notifier).select(selected);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user =
        ref.watch(authStateProvider).value ??
        ref.watch(authRepositoryProvider).currentUser;
    final profile = ref.watch(myProfileProvider).value;
    final fullName = profile?.fullName ?? user?.fullName;
    final firstName = profile?.firstName ?? fullName?.split(' ').first;
    final emirate = ref.watch(serviceLocationProvider);

    final initials = (fullName ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Semantics(
              button: true,
              label: 'Profile',
              excludeSemantics: true,
              child: GestureDetector(
                onTap: () => context.go(AppRoutes.profile),
                child: CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.lightBlue,
                  child: initials.isEmpty
                      ? const Icon(
                          Icons.person_rounded,
                          color: AppColors.primary,
                        )
                      : Text(
                          initials,
                          style: AppTypography.titleSmall.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user == null ? 'Welcome' : 'Welcome back',
                    style: AppTypography.bodySmall,
                  ),
                  Text(
                    user == null
                        ? 'Hello, guest'
                        : 'Hello, ${firstName ?? 'there'}',
                    style: AppTypography.titleLarge,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            AppIconButton(
              icon: Icons.notifications_none_rounded,
              tooltip: 'Notifications',
              onPressed: () => unawaited(context.push(AppRoutes.notifications)),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Semantics(
          button: true,
          label: 'Service location: $emirate. Change',
          excludeSemantics: true,
          child: InkWell(
            onTap: () => unawaited(_pickLocation(context, ref)),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.location_on_rounded,
                    color: AppColors.primary,
                    size: 18,
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Flexible(
                    child: Text(
                      '$emirate, UAE',
                      style: AppTypography.labelLarge,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Icon(
                    Icons.expand_more_rounded,
                    color: AppColors.textSecondary,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
