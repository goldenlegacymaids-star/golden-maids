import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_chip.dart';
import '../../data/booking_repository.dart';
import '../../domain/booking.dart';

final DateFormat _weekday = DateFormat('EEE');
final DateFormat _dayMonth = DateFormat('d MMM');
final DateFormat _longDay = DateFormat('EEEE d MMMM yyyy');
final DateFormat _time = DateFormat('h:mm a');

/// `9:00 AM` (UAE time).
String formatUaeTime(DateTime instant) => _time.format(toUae(instant));

/// `Friday 20 November 2026, 9:00 AM` (UAE time).
String formatUaeDayTime(DateTime instant) {
  final uae = toUae(instant);
  return '${_longDay.format(uae)}, ${_time.format(uae)}';
}

/// `2 hours`, `1 hour`
String hoursLabel(int hours) => hours == 1 ? '1 hour' : '$hours hours';

/// `Fri 20 Nov, 9:00 AM` (UAE time).
String formatUaeShort(DateTime instant) {
  final uae = toUae(instant);
  return '${_weekday.format(uae)} ${_dayMonth.format(uae)}, '
      '${_time.format(uae)}';
}

/// Coloured label for a booking's status.
class BookingStatusBadge extends StatelessWidget {
  const BookingStatusBadge({super.key, required this.status});

  final BookingStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      BookingStatus.pending => AppColors.warning,
      BookingStatus.completed => AppColors.success,
      BookingStatus.cancelled => AppColors.textSecondary,
      _ => AppColors.primary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.pillAll,
      ),
      child: Text(
        status.label,
        style: AppTypography.labelSmall.copyWith(
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// A horizontal row of days; closed days are shown but cannot be chosen.
class BookingDayStrip extends StatelessWidget {
  const BookingDayStrip({
    super.key,
    required this.days,
    required this.selected,
    required this.isOpen,
    required this.onSelect,
  });

  final List<DateTime> days;
  final DateTime selected;
  final bool Function(DateTime day) isOpen;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 76,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: days.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
        itemBuilder: (context, index) {
          final day = days[index];
          final open = isOpen(day);
          final isSelected = DateUtils.isSameDay(day, selected);
          final foreground = isSelected
              ? AppColors.white
              : open
              ? AppColors.textPrimary
              : AppColors.textSecondary;
          return Semantics(
            button: true,
            selected: isSelected,
            enabled: open,
            label:
                '${_longDay.format(day)}${open ? '' : ', closed'}',
            excludeSemantics: true,
            child: Material(
              color: isSelected ? AppColors.primary : AppColors.white,
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.mdAll,
                side: BorderSide(
                  color: isSelected ? AppColors.primary : AppColors.border,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: open ? () => onSelect(day) : null,
                child: SizedBox(
                  width: 64,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _weekday.format(day),
                        style: AppTypography.labelSmall.copyWith(
                          color: foreground,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _dayMonth.format(day),
                        style: AppTypography.labelMedium.copyWith(
                          color: foreground,
                          decoration: open ? null : TextDecoration.lineThrough,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Start times for the chosen day; taken times are greyed out.
class BookingSlotPicker extends ConsumerWidget {
  const BookingSlotPicker({
    super.key,
    required this.slotsKey,
    required this.selected,
    required this.isOpenDay,
    required this.onSelect,
  });

  final (String, String, int?) slotsKey;
  final DateTime? selected;
  final bool isOpenDay;
  final ValueChanged<DateTime> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!isOpenDay) {
      return const Text(
        'We are closed on this day. Please choose another day.',
        style: AppTypography.bodyMedium,
      );
    }
    final slots = ref.watch(timeSlotsProvider(slotsKey));
    return slots.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppFailure.from(error).message,
            style: AppTypography.bodyMedium.copyWith(color: AppColors.error),
          ),
          TextButton(
            onPressed: () => ref.invalidate(timeSlotsProvider(slotsKey)),
            child: const Text('Try again'),
          ),
        ],
      ),
      data: (list) {
        if (!list.any((slot) => slot.isAvailable)) {
          return const Text(
            'No free times on this day. Please try another day.',
            style: AppTypography.bodyMedium,
          );
        }
        final chosen = selected;
        return Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final slot in list)
              if (slot.isAvailable)
                AppChip(
                  label: formatUaeTime(slot.startsAt),
                  selected:
                      chosen != null &&
                      slot.startsAt.isAtSameMomentAs(chosen),
                  onTap: () => onSelect(slot.startsAt),
                )
              else
                _TakenSlot(label: formatUaeTime(slot.startsAt)),
          ],
        );
      },
    );
  }
}

/// A start time that cannot be booked (taken, or too soon).
class _TakenSlot extends StatelessWidget {
  const _TakenSlot({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label, not available',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: const ShapeDecoration(
          color: AppColors.veryLightBlue,
          shape: StadiumBorder(side: BorderSide(color: AppColors.border)),
        ),
        child: Text(
          label,
          style: AppTypography.labelMedium.copyWith(
            color: AppColors.textSecondary,
            decoration: TextDecoration.lineThrough,
          ),
        ),
      ),
    );
  }
}
