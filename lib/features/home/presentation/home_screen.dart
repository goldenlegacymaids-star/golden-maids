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
import '../../../core/widgets/app_network_image.dart';
import '../../../core/widgets/app_refresh_indicator.dart';
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

/// Home tab: greeting and location, offers, search, hiring a maid (GCC
/// Sponsor or Company visa), service categories, featured maids and popular
/// services.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref
      ..invalidate(categoriesProvider)
      ..invalidate(popularServicesProvider)
      ..invalidate(promotionsProvider)
      ..invalidate(hireCardPhotosProvider)
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
            child: AppRefreshIndicator(
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
                  const PromoCarousel(),
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
                  const SizedBox(height: AppSpacing.xl),
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

/// The two ways to hire, as photo cards (photos set by administrators on
/// the staff website; without one, the card shows its brand colour). Each
/// opens the maid list on that visa; the buttons pick the location too.
class _HireRoutes extends ConsumerWidget {
  const _HireRoutes();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photos = ref.watch(hireCardPhotosProvider).value ?? const {};
    final catalog = ref.watch(catalogRepositoryProvider);
    return Column(
      children: [
        _HireRouteCard(
          visa: VisaRoute.sponsor,
          subtitle: '2 years · you sponsor · one-off price',
          photoUrl: catalog.imageUrl(photos[VisaRoute.sponsor.value]),
          colors: const [Color(0xFF8A5A00), Color(0xFFC98B12)],
          fade: const Color(0xD95A3C00),
        ),
        const SizedBox(height: AppSpacing.sm),
        _HireRouteCard(
          visa: VisaRoute.company,
          subtitle: 'On our visa · pay monthly · flexible',
          photoUrl: catalog.imageUrl(photos[VisaRoute.company.value]),
          colors: const [Color(0xFF123E82), Color(0xFF2F7FE0)],
          fade: const Color(0xE0123E82),
        ),
      ],
    );
  }
}

class _HireRouteCard extends StatelessWidget {
  const _HireRouteCard({
    required this.visa,
    required this.subtitle,
    required this.photoUrl,
    required this.colors,
    required this.fade,
  });

  final VisaRoute visa;
  final String subtitle;
  final String? photoUrl;

  /// Brand colours used when there is no photo.
  final List<Color> colors;

  /// Dark tint behind the text, so it stays readable on any photo.
  final Color fade;

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    return Semantics(
      container: true,
      child: ClipRRect(
        borderRadius: AppRadius.lgAll,
        child: SizedBox(
          height: 156,
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: colors,
                  ),
                ),
              ),
              if (url != null) AppNetworkImage(url: url),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      fade,
                      fade.withValues(alpha: 0.35),
                      fade.withValues(alpha: 0),
                    ],
                    stops: const [0, 0.7, 1],
                  ),
                ),
              ),
              Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: () => unawaited(
                    context.push(AppRoutes.maidsFor(visa: visa.value)),
                  ),
                ),
              ),
              Positioned(
                left: AppSpacing.md,
                right: AppSpacing.md,
                bottom: AppSpacing.sm + 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    IgnorePointer(
                      child: Text(
                        visa.label,
                        style: AppTypography.headlineSmall.copyWith(
                          color: AppColors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IgnorePointer(
                      child: Text(
                        subtitle,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        _RouteLocationButton(
                          visa: visa,
                          location: MaidLocation.inUae,
                          label: 'In the UAE',
                          filled: true,
                        ),
                        _RouteLocationButton(
                          visa: visa,
                          location: MaidLocation.outsideUae,
                          label: 'From abroad',
                          filled: false,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "In the UAE" / "From abroad": opens the list on that visa and place.
class _RouteLocationButton extends StatelessWidget {
  const _RouteLocationButton({
    required this.visa,
    required this.location,
    required this.label,
    required this.filled,
  });

  final VisaRoute visa;
  final MaidLocation location;
  final String label;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${visa.label}, ${location.label}',
      excludeSemantics: true,
      child: Material(
        color: filled
            ? AppColors.white
            : AppColors.white.withValues(alpha: 0.18),
        shape: StadiumBorder(
          side: filled
              ? BorderSide.none
              : BorderSide(color: AppColors.white.withValues(alpha: 0.8)),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => unawaited(
            context.push(
              AppRoutes.maidsFor(visa: visa.value, location: location.value),
            ),
          ),
          child: Container(
            constraints: const BoxConstraints(minHeight: 36),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            alignment: Alignment.center,
            child: Text(
              label,
              style: AppTypography.labelMedium.copyWith(
                color: filled ? const Color(0xFF1F3A66) : AppColors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
