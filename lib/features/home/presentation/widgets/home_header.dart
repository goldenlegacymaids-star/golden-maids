import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/constants/uae.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_icon_button.dart';
import '../../../../core/widgets/app_logo.dart';
import '../../data/service_location.dart';

/// App title and notifications, then the service location.
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
    final emirate = ref.watch(serviceLocationProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: _BrandTitle()),
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

/// The app icon and "Golden Maids", in the logo's colours.
class _BrandTitle extends StatelessWidget {
  const _BrandTitle();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      label: AppConstants.appName,
      excludeSemantics: true,
      child: const Row(
        children: [
          AppLogo.icon(size: 32),
          SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: 'Golden '),
                  TextSpan(
                    text: 'Maids',
                    style: TextStyle(color: AppColors.primary),
                  ),
                ],
              ),
              style: AppTypography.titleLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
