import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/env.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_search_bar.dart';
import '../../../core/widgets/section_error.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/skeleton.dart';
import '../../services/data/catalog_repository.dart';
import '../../services/domain/catalog.dart';
import '../../services/presentation/catalog_display.dart';
import '../../services/presentation/widgets/service_tiles.dart';
import 'widgets/home_header.dart';
import 'widgets/promo_carousel.dart';

/// Home tab: greeting and location, search, offers, service categories and
/// popular services. ("Featured Maids" is added with recruitment in Phase 2.)
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref
      ..invalidate(categoriesProvider)
      ..invalidate(popularServicesProvider)
      ..invalidate(promotionsProvider);
    try {
      await Future.wait<Object>([
        ref.read(categoriesProvider.future),
        ref.read(popularServicesProvider.future),
        ref.read(promotionsProvider.future),
      ]);
    } on Object {
      // Each section shows its own error with a retry link.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    const screen = EdgeInsets.symmetric(
      horizontal: AppSpacing.screenPadding,
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: DecoratedBox(
          decoration: const BoxDecoration(gradient: AppColors.backgroundWash),
          child: SafeArea(
            bottom: false,
            child: RefreshIndicator(
              onRefresh: () => _refresh(ref),
              child: ListView(
                padding: EdgeInsets.only(
                  top: AppSpacing.md,
                  bottom: bottomInset + AppSpacing.xl,
                ),
                children: [
                  const Padding(padding: screen, child: HomeHeader()),
                  const SizedBox(height: AppSpacing.lg),
                  const Padding(
                    padding: screen,
                    child: Text(
                      'What services do you want to use?',
                      style: AppTypography.headlineMedium,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Padding(
                    padding: screen,
                    child: AppSearchBar(
                      readOnly: true,
                      onTap: () => unawaited(context.push(AppRoutes.search)),
                      onFilterPressed: () =>
                          unawaited(context.push(AppRoutes.search)),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const PromoCarousel(),
                  const SizedBox(height: AppSpacing.xl),
                  const Padding(
                    padding: screen,
                    child: SectionHeader(title: 'Categories'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const _CategoryStrip(),
                  const SizedBox(height: AppSpacing.xl),
                  const Padding(
                    padding: screen,
                    child: SectionHeader(title: 'Popular Services'),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const _PopularServices(),
                  if (!Env.isProduction) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Padding(
                      padding: screen,
                      child: AppButton(
                        label: 'Design preview (development only)',
                        variant: AppButtonVariant.text,
                        onPressed: () =>
                            unawaited(context.push(AppRoutes.designPreview)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Height that fits [baseText] logical pixels of text at the user's text
/// size (accessibility setting), plus [fixed] pixels of non-text content.
double _scaledHeight(BuildContext context, double fixed, double baseText) {
  final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
  return fixed + baseText * scale;
}

class _CategoryStrip extends ConsumerWidget {
  const _CategoryStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categories = ref.watch(categoriesProvider);
    final catalog = ref.watch(catalogRepositoryProvider);

    return SizedBox(
      // 64 px icon + spacing, then two lines of label text.
      height: _scaledHeight(context, 80, 38),
      child: categories.when(
        loading: () => ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenPadding,
          ),
          itemCount: 5,
          separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
          itemBuilder: (_, _) => const Skeleton(
            child: Column(
              children: [
                SkeletonBox.circle(size: 64),
                SizedBox(height: AppSpacing.xs),
                SkeletonBox(width: 64, height: 12),
              ],
            ),
          ),
        ),
        error: (error, _) => Center(
          child: SectionError(
            error: error,
            onRetry: () => ref.invalidate(categoriesProvider),
          ),
        ),
        data: (items) => ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenPadding,
          ),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
          itemBuilder: (context, index) {
            final category = items[index];
            return CategoryTile(
              category: category,
              imageUrl: catalog.imageUrl(category.imagePath),
              onTap: () =>
                  unawaited(context.push(AppRoutes.category(category.slug))),
            );
          },
        ),
      ),
    );
  }
}

class _PopularServices extends ConsumerWidget {
  const _PopularServices();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 110 px image + padding, then a two-line title and the price.
    final height = _scaledHeight(context, 140, 62);
    final services = ref.watch(popularServicesProvider);
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final catalog = ref.watch(catalogRepositoryProvider);

    IconData iconFor(HomeService service) {
      for (final category in categories) {
        if (category.id == service.categoryId) {
          return categoryIcon(category.icon);
        }
      }
      return categoryIcon('');
    }

    return services.when(
      loading: () => SizedBox(
        height: height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenPadding,
          ),
          itemCount: 3,
          separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
          itemBuilder: (_, _) => Skeleton(
            child: SkeletonBox(
              width: ServiceCard.width,
              height: height,
              borderRadius: AppRadius.lgAll,
            ),
          ),
        ),
      ),
      error: (error, _) => SectionError(
        error: error,
        onRetry: () => ref.invalidate(popularServicesProvider),
      ),
      data: (items) => items.isEmpty
          ? const SizedBox.shrink()
          : SizedBox(
              height: height,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenPadding,
                ),
                itemCount: items.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(width: AppSpacing.md),
                itemBuilder: (context, index) {
                  final service = items[index];
                  return ServiceCard(
                    service: service,
                    imageUrl: catalog.imageUrl(service.imagePath),
                    icon: iconFor(service),
                    onTap: () =>
                        unawaited(context.push(AppRoutes.service(service.slug))),
                  );
                },
              ),
            ),
    );
  }
}
