import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../../domain/catalog.dart';
import '../catalog_display.dart';

/// Service image, or an icon panel when no image has been uploaded.
class ServiceImage extends StatelessWidget {
  const ServiceImage({
    super.key,
    required this.imageUrl,
    required this.icon,
    this.width,
    this.height,
    this.borderRadius = BorderRadius.zero,
    this.iconSize = 36,
  });

  final String? imageUrl;
  final IconData icon;
  final double? width;
  final double? height;
  final BorderRadius borderRadius;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: Container(
          width: width,
          height: height,
          color: AppColors.lightBlue,
          alignment: Alignment.center,
          child: Icon(icon, size: iconSize, color: AppColors.primary),
        ),
      );
    }
    return AppNetworkImage(
      url: imageUrl,
      width: width,
      height: height,
      borderRadius: borderRadius,
    );
  }
}

/// Vertical card for horizontal "Popular Services" lists.
class ServiceCard extends StatelessWidget {
  const ServiceCard({
    super.key,
    required this.service,
    required this.imageUrl,
    required this.icon,
    required this.onTap,
  });

  static const double width = 200;

  final HomeService service;
  final String? imageUrl;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: AppCard(
        padding: EdgeInsets.zero,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ServiceImage(imageUrl: imageUrl, icon: icon, height: 110),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    service.name,
                    style: AppTypography.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    priceLabel(service),
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.primary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal row for service lists (category, search).
class ServiceListTile extends StatelessWidget {
  const ServiceListTile({
    super.key,
    required this.service,
    required this.imageUrl,
    required this.icon,
    required this.onTap,
  });

  final HomeService service;
  final String? imageUrl;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        children: [
          ServiceImage(
            imageUrl: imageUrl,
            icon: icon,
            width: 72,
            height: 72,
            iconSize: 30,
            borderRadius: AppRadius.mdAll,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  service.name,
                  style: AppTypography.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (service.shortDescription.isNotEmpty)
                  Text(
                    service.shortDescription,
                    style: AppTypography.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  priceLabel(service),
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            color: AppColors.textSecondary,
          ),
        ],
      ),
    );
  }
}

/// Round category button for the home screen.
class CategoryTile extends StatelessWidget {
  const CategoryTile({
    super.key,
    required this.category,
    required this.imageUrl,
    required this.onTap,
  });

  static const double width = 84;

  final ServiceCategory category;
  final String? imageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: category.name,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.mdAll,
        child: SizedBox(
          width: width,
          child: Column(
            children: [
              ServiceImage(
                imageUrl: imageUrl,
                icon: categoryIcon(category.icon),
                width: 64,
                height: 64,
                iconSize: 28,
                borderRadius: AppRadius.pillAll,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                category.name,
                style: AppTypography.labelMedium,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
