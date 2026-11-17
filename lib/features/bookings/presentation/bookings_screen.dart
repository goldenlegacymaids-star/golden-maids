import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_refresh_indicator.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/tab_screen.dart';
import '../../authentication/data/auth_providers.dart';
import '../../authentication/presentation/widgets/sign_in_prompt.dart';
import '../data/booking_repository.dart';
import '../domain/booking.dart';
import 'widgets/booking_widgets.dart';

/// Bookings tab: the customer's bookings by Upcoming, Active, Completed and
/// Cancelled.
class BookingsScreen extends ConsumerWidget {
  const BookingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user =
        ref.watch(authStateProvider).value ??
        ref.watch(authRepositoryProvider).currentUser;

    if (user == null) {
      return const TabScreen(
        title: 'Bookings',
        child: SignInPrompt(
          icon: Icons.calendar_today_rounded,
          title: 'Sign in to see your bookings',
          message: 'Track upcoming, active and past home-service bookings '
              'in one place.',
        ),
      );
    }

    final bookings = ref.watch(myBookingsProvider);

    return TabScreen(
      title: 'Bookings',
      scrollable: false,
      child: DefaultTabController(
        length: BookingTab.values.length,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenPadding - AppSpacing.md,
              ),
              child: TabBar(
                isScrollable: true,
                tabs: [
                  for (final tab in BookingTab.values) Tab(text: tab.label),
                ],
              ),
            ),
            Expanded(
              child: bookings.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => SingleChildScrollView(
                  child: ErrorState(
                    failure: AppFailure.from(error),
                    onRetry: () => ref.invalidate(myBookingsProvider),
                  ),
                ),
                data: (list) => TabBarView(
                  children: [
                    for (final tab in BookingTab.values)
                      _BookingList(tab: tab, bookings: _forTab(list, tab)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Upcoming bookings soonest first; the rest most recent first.
  static List<Booking> _forTab(List<Booking> all, BookingTab tab) {
    final list = all.where((booking) => booking.tab == tab).toList();
    if (tab == BookingTab.upcoming) {
      list.sort((a, b) => a.startsAt.compareTo(b.startsAt));
    } else {
      list.sort((a, b) => b.startsAt.compareTo(a.startsAt));
    }
    return list;
  }
}

class _BookingList extends ConsumerWidget {
  const _BookingList({required this.tab, required this.bookings});

  final BookingTab tab;
  final List<Booking> bookings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> refresh() async {
      ref.invalidate(myBookingsProvider);
      try {
        await ref.read(myBookingsProvider.future);
      } on Object {
        // Shown in place of the lists.
      }
    }

    if (bookings.isEmpty) {
      final name = tab.label.toLowerCase();
      final isUpcoming = tab == BookingTab.upcoming;
      return AppRefreshIndicator(
        onRefresh: refresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: EmptyState(
            icon: Icons.event_available_rounded,
            title: 'No $name bookings',
            message: isUpcoming
                ? 'When you book a home service, it will appear here.'
                : 'Your $name bookings will appear here.',
            actionLabel: isUpcoming ? 'Browse services' : null,
            onAction: isUpcoming ? () => context.go(AppRoutes.home) : null,
          ),
        ),
      );
    }

    return AppRefreshIndicator(
      onRefresh: refresh,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.screenPadding,
          AppSpacing.md,
          AppSpacing.screenPadding,
          AppSpacing.xl,
        ),
        itemCount: bookings.length,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) => BookingCard(booking: bookings[index]),
      ),
    );
  }
}

/// A booking in the list; opens its details.
class BookingCard extends StatelessWidget {
  const BookingCard({super.key, required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final staff = booking.staffName;
    return AppCard(
      onTap: () => unawaited(context.push(AppRoutes.booking(booking.id))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  booking.serviceName,
                  style: AppTypography.titleSmall,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              BookingStatusBadge(status: booking.status),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              const Icon(
                Icons.schedule_rounded,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.xxs),
              Expanded(
                child: Text(
                  [
                    formatUaeShort(booking.startsAt),
                    if (booking.hours case final hours?) hoursLabel(hours),
                  ].join(' · '),
                  style: AppTypography.bodyMedium,
                ),
              ),
            ],
          ),
          Row(
            children: [
              const Icon(
                Icons.place_rounded,
                size: 16,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: AppSpacing.xxs),
              Expanded(
                child: Text(
                  '${booking.area}, ${booking.emirate}',
                  style: AppTypography.bodySmall,
                ),
              ),
            ],
          ),
          if (staff != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text('Professional: $staff', style: AppTypography.bodySmall),
          ],
          const SizedBox(height: AppSpacing.xxs),
          Text(
            booking.reference,
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
