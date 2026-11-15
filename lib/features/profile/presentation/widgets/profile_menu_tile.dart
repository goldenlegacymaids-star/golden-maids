import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// A row in the profile menu.
///
/// When [onTap] is null the item is shown as "Coming soon" and cannot be
/// tapped, so nothing looks clickable unless it works.
class ProfileMenuTile extends StatelessWidget {
  const ProfileMenuTile({
    super.key,
    required this.icon,
    required this.title,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback? onTap;

  bool get _comingSoon => onTap == null;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: !_comingSoon,
      enabled: !_comingSoon,
      label: _comingSoon ? '$title, coming soon' : title,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _comingSoon
                      ? AppColors.veryLightBlue
                      : AppColors.lightBlue,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: _comingSoon
                      ? AppColors.textSecondary
                      : AppColors.primary,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.bodyLarge.copyWith(
                    color: _comingSoon
                        ? AppColors.textSecondary
                        : AppColors.textPrimary,
                  ),
                ),
              ),
              if (_comingSoon)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: 3,
                  ),
                  decoration: const BoxDecoration(
                    color: AppColors.veryLightBlue,
                    borderRadius: AppRadius.pillAll,
                  ),
                  child: const Text(
                    'Coming soon',
                    style: AppTypography.labelSmall,
                  ),
                )
              else
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.textSecondary,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
