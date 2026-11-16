import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/phone_number.dart';
import '../../domain/hiring_request.dart';

final DateFormat _day = DateFormat('d MMM yyyy');
final DateFormat _dayTime = DateFormat('d MMM yyyy, h:mm a');

/// `12 Nov 2026`
String formatDay(DateTime date) => _day.format(date.toLocal());

/// `12 Nov 2026, 3:45 PM`
String formatDayTime(DateTime date) => _dayTime.format(date.toLocal());

/// `1 month`, `12 months`
String monthsLabel(int months) => months == 1 ? '1 month' : '$months months';

/// Country name for a GCC ISO code, e.g. `AE` → United Arab Emirates.
String gccCountryName(String isoCode) {
  for (final country in GccCountries.all) {
    if (country.isoCode == isoCode) return country.name;
  }
  return isoCode;
}

/// Coloured label for a hiring request's status.
class HiringStatusBadge extends StatelessWidget {
  const HiringStatusBadge({super.key, required this.status});

  final HiringStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      HiringStatus.completed || HiringStatus.offerAccepted => AppColors.success,
      HiringStatus.underReview || HiringStatus.visaProcessing =>
        AppColors.warning,
      HiringStatus.rejected => AppColors.error,
      HiringStatus.cancelled => AppColors.textSecondary,
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

/// A large selectable option (visa type, package, "let the agency
/// recommend").
class OptionCard extends StatelessWidget {
  const OptionCard({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.trailing,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final String? trailing;
  final IconData? icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitleText = subtitle;
    final trailingText = trailing;
    final optionIcon = icon;

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.lightBlue : AppColors.white,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.lgAll,
          side: BorderSide(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.lgAll,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                if (optionIcon != null) ...[
                  Icon(optionIcon, color: AppColors.primary),
                  const SizedBox(width: AppSpacing.sm),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppTypography.titleSmall),
                      if (subtitleText != null)
                        Text(subtitleText, style: AppTypography.bodySmall),
                      if (trailingText != null) ...[
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          trailingText,
                          style: AppTypography.labelMedium.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? AppColors.primary : AppColors.border,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Label / value row for summaries.
class SummaryRow extends StatelessWidget {
  const SummaryRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: AppTypography.bodySmall,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(value, style: AppTypography.bodyMedium)),
        ],
      ),
    );
  }
}
