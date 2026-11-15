import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/skeleton.dart';
import '../data/catalog_repository.dart';
import 'catalog_display.dart';
import 'widgets/service_tiles.dart';

/// Services in one category.
class CategoryScreen extends ConsumerWidget {
  const CategoryScreen({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final category = ref.watch(categoryProvider(slug));
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return PageScaffold(
      title: category.value?.name ?? '',
      body: category.when(
        loading: () => const _ListSkeleton(),
        error: (error, _) => ErrorState(
          failure: AppFailure.from(error),
          onRetry: () => ref.invalidate(categoryProvider(slug)),
        ),
        data: (category) {
          final services = ref.watch(categoryServicesProvider(category.id));
          final catalog = ref.watch(catalogRepositoryProvider);
          final icon = categoryIcon(category.icon);

          return services.when(
            loading: () => const _ListSkeleton(),
            error: (error, _) => ErrorState(
              failure: AppFailure.from(error),
              onRetry: () =>
                  ref.invalidate(categoryServicesProvider(category.id)),
            ),
            data: (items) => ListView(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                AppSpacing.xs,
                AppSpacing.screenPadding,
                bottomInset + AppSpacing.xl,
              ),
              children: [
                if (category.description.isNotEmpty) ...[
                  Text(
                    category.description,
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (items.isEmpty)
                  const EmptyState(
                    icon: Icons.home_repair_service_rounded,
                    title: 'No services yet',
                    message: 'Services in this category will appear here.',
                  )
                else
                  for (final service in items) ...[
                    ServiceListTile(
                      service: service,
                      imageUrl: catalog.imageUrl(service.imagePath),
                      icon: icon,
                      onTap: () => unawaited(
                        context.push(AppRoutes.service(service.slug)),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.screenPadding),
      child: Skeleton(
        child: Column(
          children: [
            for (var i = 0; i < 4; i++) ...[
              const SkeletonBox(height: 96, borderRadius: AppRadius.lgAll),
              const SizedBox(height: AppSpacing.sm),
            ],
          ],
        ),
      ),
    );
  }
}
