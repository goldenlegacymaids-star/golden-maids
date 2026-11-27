import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../../../../core/widgets/page_indicator.dart';
import '../../../../core/widgets/section_error.dart';
import '../../../services/data/catalog_repository.dart';
import '../../../services/domain/catalog.dart';

/// Home-screen banners managed by administrators (`public.promotions`).
/// Hidden when there are no live banners.
class PromoCarousel extends ConsumerWidget {
  const PromoCarousel({super.key});

  static const double height = 172;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final promotions = ref.watch(promotionsProvider);

    return promotions.when(
      loading: () => const _BannerPlaceholder(),
      error: (error, _) => SectionError(
        error: error,
        onRetry: () => ref.invalidate(promotionsProvider),
      ),
      data: (items) => items.isEmpty
          ? const SizedBox.shrink()
          : _Carousel(
              promotions: items,
              imageUrl: ref.watch(catalogRepositoryProvider).imageUrl,
            ),
    );
  }
}

class _Carousel extends StatefulWidget {
  const _Carousel({required this.promotions, required this.imageUrl});

  final List<Promotion> promotions;
  final String? Function(String?) imageUrl;

  @override
  State<_Carousel> createState() => _CarouselState();
}

class _CarouselState extends State<_Carousel> {
  static const Duration _autoAdvance = Duration(seconds: 5);

  final _controller = PageController();
  Timer? _timer;
  int _index = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _timer?.cancel();
    // Auto-advance unless the user prefers reduced motion.
    if (widget.promotions.length > 1 &&
        !MediaQuery.disableAnimationsOf(context)) {
      _timer = Timer.periodic(_autoAdvance, (_) => _advance());
    }
  }

  void _advance() {
    if (!_controller.hasClients) return;
    final next = (_index + 1) % widget.promotions.length;
    unawaited(
      _controller.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  /// Every offer opens the hire page: all maids, unfiltered (as on the
  /// website).
  void _open(Promotion promotion) {
    unawaited(context.push(AppRoutes.maids));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: PromoCarousel.height,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.promotions.length,
            onPageChanged: (index) => setState(() => _index = index),
            itemBuilder: (context, index) {
              final promotion = widget.promotions[index];
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenPadding,
                ),
                child: _Banner(
                  promotion: promotion,
                  imageUrl: widget.imageUrl(promotion.imagePath),
                  onAction: () => _open(promotion),
                ),
              );
            },
          ),
        ),
        if (widget.promotions.length > 1) ...[
          const SizedBox(height: AppSpacing.sm),
          PageIndicator(count: widget.promotions.length, index: _index),
        ],
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.promotion,
    required this.imageUrl,
    required this.onAction,
  });

  final Promotion promotion;
  final String? imageUrl;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final discount = promotion.discountPercent;
    const white = TextStyle(color: AppColors.white);

    return Semantics(
      container: true,
      label: [
        if (discount != null) '${Formatters.percent(discount)} off',
        promotion.title,
        promotion.subtitle,
      ].where((part) => part.isNotEmpty).join(', '),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.primary,
          borderRadius: AppRadius.xlAll,
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.xs,
                  AppSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (discount != null)
                      Text(
                        '${Formatters.percent(discount)} OFF',
                        style: AppTypography.headlineMedium.merge(white),
                        maxLines: 1,
                      ),
                    // Flexible so long admin-entered text never overflows.
                    Flexible(
                      child: Text(
                        promotion.title,
                        style: AppTypography.titleMedium.merge(white),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (promotion.subtitle.isNotEmpty)
                      Flexible(
                        child: Text(
                          promotion.subtitle,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.lightBlue,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (promotion.hasAction) ...[
                      const SizedBox(height: AppSpacing.sm),
                      AppButton(
                        label: promotion.ctaLabel,
                        variant: AppButtonVariant.dark,
                        compact: true,
                        expand: false,
                        onPressed: onAction,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (imageUrl != null)
              Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: AppNetworkImage(
                  url: imageUrl,
                  width: 128,
                  height: double.infinity,
                  borderRadius: AppRadius.lgAll,
                  semanticLabel: promotion.title,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Shown while the first banners load: the banner's blue shape with a soft
/// shimmer, so the space reads as "loading", not empty.
class _BannerPlaceholder extends StatelessWidget {
  const _BannerPlaceholder();

  @override
  Widget build(BuildContext context) {
    final box = Container(
      height: PromoCarousel.height,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.85),
        borderRadius: AppRadius.xlAll,
      ),
    );
    return Semantics(
      label: 'Loading offers',
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenPadding,
        ),
        child: MediaQuery.disableAnimationsOf(context)
            ? box
            : Shimmer.fromColors(
                baseColor: AppColors.primary.withValues(alpha: 0.55),
                highlightColor: AppColors.primary.withValues(alpha: 0.3),
                child: box,
              ),
      ),
    );
  }
}
