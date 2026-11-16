import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/agency_contact.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../data/booking_repository.dart';
import '../domain/booking.dart';
import 'booking_details_screen.dart';
import 'widgets/booking_widgets.dart';

/// Choose a new day and time for a booking (until the cancellation limit).
class RescheduleBookingScreen extends ConsumerWidget {
  const RescheduleBookingScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final booking = ref.watch(bookingProvider(bookingId));
    final settings = ref.watch(bookingSettingsProvider);

    return PageScaffold(
      title: 'Reschedule',
      body: switch ((booking, settings)) {
        (AsyncData(value: final b), AsyncData(value: final rules)) =>
          b.canChange(rules)
              ? _Reschedule(booking: b, settings: rules)
              : const SingleChildScrollView(
                  child: ErrorState(
                    failure: PermissionFailure(
                      message:
                          'This booking can no longer be changed in the app. '
                          'Please call us on ${AgencyContact.phoneDisplay}.',
                    ),
                  ),
                ),
        (AsyncError(:final error), _) || (_, AsyncError(:final error)) =>
          SingleChildScrollView(
            child: ErrorState(
              failure: AppFailure.from(error),
              onRetry: () {
                ref
                  ..invalidate(bookingProvider(bookingId))
                  ..invalidate(bookingSettingsProvider);
              },
            ),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Reschedule extends ConsumerStatefulWidget {
  const _Reschedule({required this.booking, required this.settings});

  final Booking booking;
  final BookingSettings settings;

  @override
  ConsumerState<_Reschedule> createState() => _RescheduleState();
}

class _RescheduleState extends ConsumerState<_Reschedule> {
  late DateTime _day = _initialDay();
  DateTime? _slot;
  bool _saving = false;
  String? _error;

  Booking get _booking => widget.booking;

  (String, String, int?) get _slotsKey => (
    _booking.serviceId,
    isoDate(_day),
    _booking.bookingType == BookingType.hourly ? _booking.hours : null,
  );

  /// The booking's current day, if it can still be chosen.
  DateTime _initialDay() {
    final days = widget.settings.bookableDays();
    final current = toUae(_booking.startsAt);
    for (final day in days) {
      if (DateUtils.isSameDay(day, current) && widget.settings.isOpenOn(day)) {
        return day;
      }
    }
    return days.firstWhere(widget.settings.isOpenOn, orElse: () => days.first);
  }

  bool get _isNewTime {
    final slot = _slot;
    return slot != null && !slot.isAtSameMomentAs(_booking.startsAt);
  }

  Future<void> _save() async {
    final slot = _slot;
    if (slot == null || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(bookingRepositoryProvider)
          .rescheduleBooking(_booking.id, slot);
      if (!mounted) return;
      refreshBooking(ref, _booking.id);
      showAppSnackBar(
        context,
        'Moved to ${formatUaeShort(slot)}. Our team will confirm the new '
        'time.',
      );
      context.pop();
    } on Object catch (error) {
      if (!mounted) return;
      ref.invalidate(timeSlotsProvider(_slotsKey));
      setState(() {
        _saving = false;
        _slot = null;
        _error = AppFailure.from(error).message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final error = _error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              AppSpacing.xs,
              AppSpacing.screenPadding,
              AppSpacing.xl,
            ),
            children: [
              AppCard(
                color: AppColors.veryLightBlue,
                shadow: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _booking.serviceName,
                      style: AppTypography.titleSmall,
                    ),
                    Text(
                      'Now: ${formatUaeDayTime(_booking.startsAt)}',
                      style: AppTypography.bodyMedium,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const Text('New day', style: AppTypography.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              BookingDayStrip(
                days: widget.settings.bookableDays(),
                selected: _day,
                isOpen: widget.settings.isOpenOn,
                onSelect: (day) => setState(() {
                  _day = day;
                  _slot = null;
                }),
              ),
              const SizedBox(height: AppSpacing.lg),
              const Text('New time', style: AppTypography.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              BookingSlotPicker(
                slotsKey: _slotsKey,
                selected: _slot,
                isOpenDay: widget.settings.isOpenOn(_day),
                onSelect: (slot) => setState(() {
                  _slot = slot;
                  _error = null;
                }),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'All times are UAE time. After you reschedule, our team '
                'confirms the new time and assigns a professional again.',
                style: AppTypography.bodySmall,
              ),
              if (error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  error,
                  style: AppTypography.bodyMedium.copyWith(
                    color: AppColors.error,
                  ),
                ),
              ],
            ],
          ),
        ),
        DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.white,
            boxShadow: AppShadows.soft,
          ),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              AppSpacing.sm,
              AppSpacing.screenPadding,
              bottomInset + AppSpacing.sm,
            ),
            child: AppButton(
              label: 'Confirm new time',
              isLoading: _saving,
              onPressed: _isNewTime && !_saving ? _save : null,
            ),
          ),
        ),
      ],
    );
  }
}
