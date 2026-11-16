import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/agency_contact.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../candidates/presentation/candidate_profile_screen.dart';
import '../../hiring/presentation/widgets/hiring_widgets.dart';
import '../data/booking_repository.dart';
import '../domain/booking.dart';
import 'widgets/booking_widgets.dart';

/// Refreshes everything that shows [bookingId].
void refreshBooking(WidgetRef ref, String bookingId) {
  ref
    ..invalidate(bookingProvider(bookingId))
    ..invalidate(bookingHistoryProvider(bookingId))
    ..invalidate(myBookingsProvider);
}

/// One booking: details, professional, timeline, cancel and reschedule.
class BookingDetailsScreen extends ConsumerWidget {
  const BookingDetailsScreen({super.key, required this.bookingId});

  final String bookingId;

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const _CancelDialog(),
    );
    if (reason == null) return;
    try {
      await ref
          .read(bookingRepositoryProvider)
          .cancelBooking(bookingId, reason: reason);
      if (!context.mounted) return;
      refreshBooking(ref, bookingId);
      showAppSnackBar(context, 'Booking cancelled.');
    } on Object catch (error) {
      if (!context.mounted) return;
      // The booking may have changed meanwhile (e.g. confirmed by staff).
      refreshBooking(ref, bookingId);
      showErrorSnackBar(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booking = ref.watch(bookingProvider(bookingId));
    final settings =
        ref.watch(bookingSettingsProvider).value ?? const BookingSettings();

    return PageScaffold(
      title: booking.value?.reference ?? 'Booking',
      body: booking.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => SingleChildScrollView(
          child: ErrorState(
            failure: AppFailure.from(error),
            onRetry: () => ref.invalidate(bookingProvider(bookingId)),
          ),
        ),
        data: (data) {
          final bottomInset = MediaQuery.paddingOf(context).bottom;
          final canChange = data.canChange(settings);
          final isRequest = data.bookingType == BookingType.request;
          final price = data.priceEstimate;
          final staff = data.staffName;
          final years = data.staffYearsExperience;

          return RefreshIndicator(
            onRefresh: () async {
              refreshBooking(ref, bookingId);
              try {
                await ref.read(bookingProvider(bookingId).future);
              } on Object {
                // Shown in place of the details.
              }
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                AppSpacing.xs,
                AppSpacing.screenPadding,
                bottomInset + AppSpacing.xl,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('Status', style: AppTypography.titleMedium),
                    ),
                    BookingStatusBadge(status: data.status),
                  ],
                ),
                if (data.status == BookingStatus.pending) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    isRequest
                        ? 'Our team will call you to confirm the time and the '
                              'price.'
                        : 'Our team will confirm your booking and assign a '
                              'professional.',
                    style: AppTypography.bodySmall,
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                if (staff != null) ...[
                  AppCard(
                    color: AppColors.veryLightBlue,
                    shadow: false,
                    child: Row(
                      children: [
                        const CircleAvatar(
                          backgroundColor: AppColors.lightBlue,
                          child: Icon(
                            Icons.person_rounded,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Your professional',
                                style: AppTypography.bodySmall,
                              ),
                              Text(staff, style: AppTypography.titleSmall),
                              if (years != null && years > 0)
                                Text(
                                  years == 1
                                      ? '1 year of experience'
                                      : '$years years of experience',
                                  style: AppTypography.bodySmall,
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SummaryRow(label: 'Service', value: data.serviceName),
                      if (data.hours case final hours?)
                        SummaryRow(label: 'Duration', value: hoursLabel(hours)),
                      SummaryRow(
                        label: isRequest ? 'Preferred time' : 'Date and time',
                        value: formatUaeDayTime(data.startsAt),
                      ),
                      SummaryRow(label: 'Address', value: data.address),
                      if (data.addressNotes.isNotEmpty)
                        SummaryRow(
                          label: 'Directions',
                          value: data.addressNotes,
                        ),
                      if (data.instructions.isNotEmpty)
                        SummaryRow(
                          label: 'Instructions',
                          value: data.instructions,
                        ),
                      SummaryRow(
                        label: 'Estimated price',
                        value: price == null
                            ? 'Confirmed by our team'
                            : Formatters.aed(price),
                      ),
                      SummaryRow(
                        label: 'Payment',
                        value: data.paymentMethod.label,
                      ),
                      SummaryRow(label: 'Reference', value: data.reference),
                      SummaryRow(
                        label: 'Booked',
                        value: formatUaeDayTime(data.createdAt),
                      ),
                      if (data.status == BookingStatus.cancelled &&
                          data.cancelReason.isNotEmpty)
                        SummaryRow(
                          label: 'Reason',
                          value: data.cancelReason,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                const Text('Progress', style: AppTypography.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                _Timeline(bookingId: bookingId),
                if (canChange) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'You can reschedule or cancel free of charge until '
                    '${formatUaeDayTime(data.changeDeadline(settings))}.',
                    style: AppTypography.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppButton(
                    label: 'Reschedule',
                    icon: Icons.edit_calendar_rounded,
                    onPressed: () => unawaited(
                      context.push(AppRoutes.rescheduleBooking(bookingId)),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppButton(
                    label: 'Cancel booking',
                    variant: AppButtonVariant.outline,
                    onPressed: () => _cancel(context, ref),
                  ),
                ] else if (data.status.isUpcoming || data.status.isActive) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    data.status.isUpcoming
                        ? 'Changes within ${settings.cancelHours} hours of '
                              'the start can only be made by phone.'
                        : 'Need help with this booking? Call our team.',
                    style: AppTypography.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  AppButton(
                    label: 'Call ${AgencyContact.phoneDisplay}',
                    icon: Icons.call_rounded,
                    variant: AppButtonVariant.outline,
                    onPressed: () => openExternal(
                      context,
                      ref,
                      AgencyContact.callUri(),
                      failureMessage:
                          'Could not open the phone app. Please call '
                          '${AgencyContact.phoneDisplay}.',
                    ),
                  ),
                ],
              ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Asks for confirmation and an optional reason; returns the reason, or
/// null to keep the booking.
class _CancelDialog extends StatefulWidget {
  const _CancelDialog();

  @override
  State<_CancelDialog> createState() => _CancelDialogState();
}

class _CancelDialogState extends State<_CancelDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cancel this booking?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('There is no charge for cancelling now.'),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _reason,
            maxLength: 500,
            maxLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Reason (optional)',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Keep booking'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_reason.text.trim()),
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          child: const Text('Cancel booking'),
        ),
      ],
    );
  }
}

class _Timeline extends ConsumerWidget {
  const _Timeline({required this.bookingId});

  final String bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(bookingHistoryProvider(bookingId));

    return history.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => ErrorState(
        failure: AppFailure.from(error),
        onRetry: () => ref.invalidate(bookingHistoryProvider(bookingId)),
      ),
      data: (events) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, event) in events.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Icon(
                      index == events.length - 1
                          ? Icons.radio_button_checked_rounded
                          : Icons.check_circle_rounded,
                      size: 18,
                      color: event.status == BookingStatus.cancelled
                          ? AppColors.textSecondary
                          : AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.status.label,
                          style: AppTypography.titleSmall,
                        ),
                        Text(
                          formatUaeDayTime(event.createdAt),
                          style: AppTypography.bodySmall,
                        ),
                        if (event.note.isNotEmpty)
                          Text(event.note, style: AppTypography.bodyMedium),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
