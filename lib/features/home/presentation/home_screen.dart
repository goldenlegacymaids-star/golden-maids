import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
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
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_search_bar.dart';
import '../../../core/widgets/section_error.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/skeleton.dart';
import '../../candidates/data/candidate_repository.dart';
import '../../candidates/domain/candidate.dart';
import '../../candidates/presentation/open_candidate.dart';
import '../../candidates/presentation/widgets/candidate_cards.dart';
import '../../services/data/catalog_repository.dart';
import '../../services/domain/catalog.dart';
import '../../services/presentation/catalog_display.dart';
import '../../services/presentation/widgets/service_tiles.dart';
import 'widgets/home_header.dart';
import 'widgets/promo_carousel.dart';

/// Home tab: greeting and location, hiring a maid (GCC Sponsor or Company
/// visa), search, offers, service categories, featured maids and popular
/// services.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref
      ..invalidate(categoriesProvider)
      ..invalidate(popularServicesProvider)
      ..invalidate(promotionsProvider)
      ..invalidate(featuredCandidatesProvider);
    try {
      await Future.wait<Object>([
        ref.read(categoriesProvider.future),
        ref.read(popularServicesProvider.future),
        ref.read(promotionsProvider.future),
        ref.read(featuredCandidatesProvider.future),
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
                // Home is short: build the lower sections early so they load
                // together with the top of the page.
                scrollCacheExtent: const ScrollCacheExtent.pixels(800),
                padding: EdgeInsets.only(
                  top: AppSpacing.md,
                  bottom: bottomInset + AppSpacing.xl,
                ),
                children: [
                  const Padding(padding: screen, child: HomeHeader()),
                  const SizedBox(height: AppSpacing.lg),
                  Padding(
                    padding: screen,
                    child: SectionHeader(
                      title: 'Hire a Maid',
                      actionLabel: 'All maids',
                      onAction: () => unawaited(context.push(AppRoutes.maids)),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const Padding(padding: screen, child: _HireRoutes()),
                  const SizedBox(height: AppSpacing.xl),
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
                  const _FeaturedMaids(),
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

/// "Featured Maids": hidden when there are none to show.
class _FeaturedMaids extends ConsumerWidget {
  const _FeaturedMaids();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 140 px photo + padding, then four lines of text (about 72 px).
    final height = _scaledHeight(context, CandidateCard.photoHeight + 28, 78);
    final candidates = ref.watch(featuredCandidatesProvider);
    final repository = ref.watch(candidateRepositoryProvider);

    final Widget content = candidates.when(
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
              width: CandidateCard.width,
              height: height,
              borderRadius: AppRadius.lgAll,
            ),
          ),
        ),
      ),
      error: (error, _) => SectionError(
        error: error,
        onRetry: () => ref.invalidate(featuredCandidatesProvider),
      ),
      data: (items) => SizedBox(
        height: height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenPadding,
          ),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.md),
          itemBuilder: (context, index) {
            final candidate = items[index];
            return CandidateCard(
              candidate: candidate,
              photoUrl: repository.photoUrl(candidate.photoPath),
              onTap: () => openCandidate(context, ref, candidate),
            );
          },
        ),
      ),
    );

    if (candidates.value?.isEmpty ?? false) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.xl),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.screenPadding,
          ),
          child: SectionHeader(
            title: 'Featured Maids',
            actionLabel: 'See All',
            onAction: () => unawaited(context.push(AppRoutes.maids)),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        content,
      ],
    );
  }
}

/// The two ways to hire: each opens the maid list on that visa.
class _HireRoutes extends StatelessWidget {
  const _HireRoutes();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _HireRouteCard(
          visa: VisaRoute.sponsor,
          icon: Icons.badge_rounded,
          subtitle: '2 years · you sponsor the maid · one-off price',
        ),
        SizedBox(height: AppSpacing.sm),
        _HireRouteCard(
          visa: VisaRoute.company,
          icon: Icons.apartment_rounded,
          subtitle: 'On our visa · pay monthly · flexible months',
        ),
      ],
    );
  }
}

class _HireRouteCard extends StatelessWidget {
  const _HireRouteCard({
    required this.visa,
    required this.icon,
    required this.subtitle,
  });

  final VisaRoute visa;
  final IconData icon;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () =>
          unawaited(context.push(AppRoutes.maidsFor(visa: visa.value))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                  color: AppColors.lightBlue,
                  borderRadius: AppRadius.mdAll,
                ),
                child: Icon(icon, color: AppColors.primary),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(visa.label, style: AppTypography.titleMedium),
                    Text(subtitle, style: AppTypography.bodySmall),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.textSecondary,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final location in MaidLocation.values)
                _RouteLocationLink(visa: visa, location: location),
            ],
          ),
        ],
      ),
    );
  }
}

/// "In the UAE" / "Outside the UAE": opens the list on that visa and place.
class _RouteLocationLink extends StatelessWidget {
  const _RouteLocationLink({required this.visa, required this.location});

  final VisaRoute visa;
  final MaidLocation location;

  @override
  Widget build(BuildContext context) {
    final inUae = location == MaidLocation.inUae;
    return Semantics(
      button: true,
      label: '${visa.label}, ${location.label}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: AppRadius.pillAll,
        onTap: () => unawaited(
          context.push(
            AppRoutes.maidsFor(visa: visa.value, location: location.value),
          ),
        ),
        child: Container(
          constraints: const BoxConstraints(minHeight: 32),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xxs + 2,
          ),
          decoration: BoxDecoration(
            color: inUae ? AppColors.successSoft : AppColors.lightBlue,
            borderRadius: AppRadius.pillAll,
          ),
          child: Text(
            location.label,
            style: AppTypography.labelSmall.copyWith(
              color: inUae ? AppColors.successText : AppColors.infoText,
            ),
          ),
        ),
      ),
    );
  }
}
