import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/skeleton.dart';
import '../../bookings/data/booking_repository.dart';
import '../../bookings/domain/booking.dart';
import '../../candidates/presentation/open_candidate.dart';
import '../data/catalog_repository.dart';
import '../domain/catalog.dart';
import 'catalog_display.dart';
import 'widgets/service_tiles.dart';

/// Service details: image, description, price and duration, with the
/// button that starts a booking.
class ServiceDetailsScreen extends ConsumerWidget {
  const ServiceDetailsScreen({super.key, required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(serviceProvider(slug));

    return service.when(
      loading: () => const PageScaffold(
        title: '',
        body: Padding(
          padding: EdgeInsets.all(AppSpacing.screenPadding),
          child: Skeleton(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBox(height: 220, borderRadius: AppRadius.xlAll),
                SizedBox(height: AppSpacing.lg),
                SkeletonBox(width: 220, height: 24),
                SizedBox(height: AppSpacing.sm),
                SkeletonBox(width: 140, height: 16),
              ],
            ),
          ),
        ),
      ),
      error: (error, _) => PageScaffold(
        title: '',
        body: ErrorState(
          failure: AppFailure.from(error),
          onRetry: () => ref.invalidate(serviceProvider(slug)),
        ),
      ),
      data: (service) => _ServiceDetails(service: service),
    );
  }
}

class _ServiceDetails extends ConsumerWidget {
  const _ServiceDetails({required this.service});

  final HomeService service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(catalogRepositoryProvider);
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final category = categories
        .where((c) => c.id == service.categoryId)
        .firstOrNull;
    final icon = categoryIcon(category?.icon ?? '');
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final duration = service.durationMinutes;
    final description = service.description.isNotEmpty
        ? service.description
        : service.shortDescription;
    final imageUrl = catalog.imageUrl(service.imagePath);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // White status-bar icons over photos; dark over the pale icon panel.
      value: imageUrl == null
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
      child: Scaffold(
        body: ListView(
          padding: EdgeInsets.only(bottom: bottomInset + AppSpacing.xl),
          children: [
            Stack(
              children: [
                ServiceImage(
                  imageUrl: imageUrl,
                  icon: icon,
                  height: 280,
                  iconSize: 72,
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    child: AppIconButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Back',
                      style: AppIconButtonStyle.translucent,
                      size: 44,
                      onPressed: () => context.canPop()
                          ? context.pop()
                          : context.go(AppRoutes.home),
                    ),
                  ),
                ),
              ],
            ),
            Transform.translate(
              offset: const Offset(0, -AppRadius.xl),
              child: Container(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.screenPadding,
                  AppSpacing.xl,
                  AppSpacing.screenPadding,
                  0,
                ),
                decoration: const BoxDecoration(
                  color: AppColors.white,
                  borderRadius: AppRadius.sheet,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (category != null)
                      Text(
                        category.name.toUpperCase(),
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.primary,
                          letterSpacing: 0.8,
                        ),
                      ),
                    const SizedBox(height: AppSpacing.xxs),
                    Semantics(
                      header: true,
                      child: Text(
                        service.name,
                        style: AppTypography.headlineMedium,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.xs,
                      children: [
                        _InfoChip(
                          icon: Icons.local_offer_rounded,
                          label: priceLabel(service),
                        ),
                        if (duration != null)
                          _InfoChip(
                            icon: Icons.timer_outlined,
                            label: Formatters.duration(duration),
                          ),
                      ],
                    ),
                    if (description.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.lg),
                      const Text('About', style: AppTypography.titleMedium),
                      const SizedBox(height: AppSpacing.xs),
                      Text(description, style: AppTypography.bodyMedium),
                    ],
                    if (service.requirements.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.lg),
                      const Text(
                        'What you need to know',
                        style: AppTypography.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        service.requirements,
                        style: AppTypography.bodyMedium,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xl),
                    _BookCard(
                      service: service,
                      isMaidVisa: category?.slug == _maidVisaCategory,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The 2-year maid visa is arranged through a hiring request.
const String _maidVisaCategory = 'maid-visa';

/// "Book now" (or "Request this service"), with a line on how it works.
class _BookCard extends ConsumerWidget {
  const _BookCard({required this.service, required this.isMaidVisa});

  final HomeService service;
  final bool isMaidVisa;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cancelHours =
        ref.watch(bookingSettingsProvider).value?.cancelHours ??
        const BookingSettings().cancelHours;
    final (label, note) = isMaidVisa
        ? (
            'Start a hiring request',
            'Choose the 2-year package and a maid, and our recruitment team '
                'will arrange the visa with you.',
          )
        : switch (service.bookingType) {
            BookingType.hourly || BookingType.visit => (
              'Book now',
              'Choose a date and time. You pay on completion, by cash or '
                  'card. Free cancellation up to $cancelHours hours before.',
            ),
            BookingType.request => (
              'Request this service',
              'Tell us your preferred time and our team will call you to '
                  'confirm the details and the price.',
            ),
          };

    void start() {
      if (!isSignedIn(ref)) {
        showSignInSheet(
          context,
          title: 'Sign in to book',
          message:
              'Create a free account or sign in to book home services and '
              'follow your bookings.',
        );
        return;
      }
      unawaited(
        context.push(
          isMaidVisa ? AppRoutes.hire() : AppRoutes.book(service.slug),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          color: AppColors.veryLightBlue,
          shadow: false,
          child: Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                color: AppColors.primary,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: Text(note, style: AppTypography.bodyMedium)),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        AppButton(
          label: label,
          icon: Icons.event_available_rounded,
          onPressed: start,
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: const BoxDecoration(
        color: AppColors.lightBlue,
        borderRadius: AppRadius.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: AppSpacing.xxs),
          Flexible(
            child: Text(
              label,
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.secondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
