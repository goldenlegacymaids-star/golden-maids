import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../../data/candidate_repository.dart';
import '../../domain/candidate.dart';
import 'favourite_button.dart';
import 'nationality_flag.dart';
import 'video_interview.dart';

/// "Housemaid · 34 yrs"
String candidateSubtitle(Candidate candidate) {
  final age = candidate.age;
  return age == null
      ? candidate.designation
      : '${candidate.designation} · $age yrs';
}

/// "6 yrs experience" / "No previous experience"
String experienceLabel(int years) => switch (years) {
  0 => 'No previous experience',
  1 => '1 yr experience',
  _ => '$years yrs experience',
};

/// "AED 1,800 / month", or null when no salary is set.
String? salaryLabel(Candidate candidate) {
  final salary = candidate.expectedSalary;
  return salary == null ? null : '${Formatters.aed(salary)} / month';
}

/// "AED 2,500 / month", "AED 9,000" or "Price on request" (prices are set
/// by administrators). For packages priced by nationality, give the maid's
/// [nationality]; without it the lowest price is shown ("From AED 9,000").
String packagePriceLabel(RecruitmentPackage package, {String? nationality}) {
  if (package.priceByNationality && nationality == null) {
    final prices = package.nationalityPrices.values;
    if (prices.isEmpty) return 'Price on request';
    final lowest = prices.reduce((a, b) => a < b ? a : b);
    return 'From ${Formatters.aed(lowest)}';
  }
  final price = package.priceFor(nationality);
  if (price == null) return 'Price on request';
  return package.priceUnit == 'per_month'
      ? '${Formatters.aed(price)} / month'
      : Formatters.aed(price);
}

final _dayMonth = DateFormat('d MMM');

/// "In the UAE · Available now", "In the UAE · From 24 Nov",
/// "Outside the UAE · Arrives in 10–20 days" or
/// "Outside the UAE · Arrival on request". [arrival] is the nationality's
/// arrival time ("10–20 days"); [now] is for tests.
String locationLabel(
  Candidate candidate, {
  String? arrival,
  DateTime? now,
}) {
  switch (candidate.location) {
    case MaidLocation.outsideUae:
      return arrival == null
          ? 'Outside the UAE · Arrival on request'
          : 'Outside the UAE · Arrives in $arrival';
    case MaidLocation.inUae:
      if (candidate.availability != CandidateAvailability.available) {
        return 'In the UAE';
      }
      final from = candidate.availableFrom;
      final today = now ?? DateTime.now();
      if (from != null &&
          from.isAfter(DateTime(today.year, today.month, today.day))) {
        return 'In the UAE · From ${_dayMonth.format(from)}';
      }
      return 'In the UAE · Available now';
  }
}

/// The nationality's arrival time ("10–20 days"), or null.
String? arrivalFor(WidgetRef ref, String nationality) {
  for (final item
      in ref.watch(maidNationalitiesProvider).value ??
          const <MaidNationality>[]) {
    if (item.name == nationality) return item.arrivalLabel;
  }
  return null;
}

/// Small label: where the maid is and when she can start.
class LocationBadge extends ConsumerWidget {
  const LocationBadge({super.key, required this.candidate});

  final Candidate candidate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inUae = candidate.location == MaidLocation.inUae;
    final label = locationLabel(
      candidate,
      arrival: arrivalFor(ref, candidate.nationality),
    );
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: inUae ? AppColors.successSoft : AppColors.lightBlue,
        borderRadius: AppRadius.pillAll,
      ),
      child: Text(
        label,
        style: AppTypography.labelSmall.copyWith(
          color: inUae ? AppColors.successText : AppColors.infoText,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Candidate photo, or a person icon when none has been uploaded.
class CandidatePhoto extends StatelessWidget {
  const CandidatePhoto({
    super.key,
    required this.url,
    required this.label,
    this.width,
    this.height,
    this.borderRadius = BorderRadius.zero,
    this.iconSize = 48,
  });

  final String? url;

  /// Accessibility label, e.g. "Photo of Maria Santos".
  final String label;
  final double? width;
  final double? height;
  final BorderRadius borderRadius;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    if (url == null) {
      return ClipRRect(
        borderRadius: borderRadius,
        child: Container(
          width: width,
          height: height,
          color: AppColors.lightBlue,
          alignment: Alignment.center,
          child: Icon(
            Icons.person_rounded,
            size: iconSize,
            color: AppColors.primary,
            semanticLabel: label,
          ),
        ),
      );
    }
    return AppNetworkImage(
      url: url,
      width: width,
      height: height,
      borderRadius: borderRadius,
      semanticLabel: label,
    );
  }
}

/// Small coloured label showing whether a candidate is available.
class AvailabilityBadge extends StatelessWidget {
  const AvailabilityBadge({super.key, required this.availability});

  final CandidateAvailability availability;

  @override
  Widget build(BuildContext context) {
    final color = switch (availability) {
      CandidateAvailability.available => AppColors.success,
      CandidateAvailability.reserved => AppColors.warning,
      _ => AppColors.textSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: AppRadius.pillAll,
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            availability.label,
            style: AppTypography.labelSmall.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

/// "TEST" label on test records, so they are never mistaken for real ones.
class TestTag extends StatelessWidget {
  const TestTag({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 2,
      ),
      decoration: const BoxDecoration(
        color: AppColors.ink,
        borderRadius: AppRadius.pillAll,
      ),
      child: Text(
        'TEST',
        style: AppTypography.labelSmall.copyWith(color: AppColors.white),
      ),
    );
  }
}

class _NationalityLine extends StatelessWidget {
  const _NationalityLine({required this.nationality});

  final String nationality;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        NationalityFlag(nationality: nationality, height: 12),
        const SizedBox(width: AppSpacing.xxs + 2),
        Expanded(
          child: Text(
            nationality,
            style: AppTypography.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// Vertical card for the horizontal "Featured Maids" list on Home.
class CandidateCard extends StatelessWidget {
  const CandidateCard({
    super.key,
    required this.candidate,
    required this.photoUrl,
    required this.onTap,
  });

  static const double width = 170;
  static const double photoHeight = 140;

  final Candidate candidate;
  final String? photoUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final salary = salaryLabel(candidate);

    return SizedBox(
      width: width,
      child: AppCard(
        padding: EdgeInsets.zero,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Stack(
              children: [
                CandidatePhoto(
                  url: photoUrl,
                  label: 'Photo of ${candidate.title}',
                  width: width,
                  height: photoHeight,
                ),
                Positioned(
                  left: AppSpacing.xs,
                  top: AppSpacing.xs,
                  child: AvailabilityBadge(
                    availability: candidate.availability,
                  ),
                ),
                if (candidate.isTest)
                  const Positioned(
                    right: AppSpacing.xs,
                    top: AppSpacing.xs,
                    child: TestTag(),
                  ),
                Positioned(
                  right: AppSpacing.xs,
                  bottom: AppSpacing.xs,
                  child: FavouriteButton(
                    candidateId: candidate.id,
                    candidateTitle: candidate.title,
                    size: 34,
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    candidate.title,
                    style: AppTypography.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    candidateSubtitle(candidate),
                    style: AppTypography.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  _NationalityLine(nationality: candidate.nationality),
                  if (salary != null)
                    Text(
                      salary,
                      style: AppTypography.labelMedium.copyWith(
                        color: AppColors.primary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontal row for the candidate directory.
class CandidateListTile extends StatelessWidget {
  const CandidateListTile({
    super.key,
    required this.candidate,
    required this.photoUrl,
    required this.onTap,
  });

  final Candidate candidate;
  final String? photoUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final salary = salaryLabel(candidate);

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CandidatePhoto(
            url: photoUrl,
            label: 'Photo of ${candidate.title}',
            width: 88,
            height: 104,
            iconSize: 36,
            borderRadius: AppRadius.mdAll,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xxs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    AvailabilityBadge(availability: candidate.availability),
                    if (candidate.isTest) const TestTag(),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  candidate.title,
                  style: AppTypography.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  candidateSubtitle(candidate),
                  style: AppTypography.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                _NationalityLine(nationality: candidate.nationality),
                const SizedBox(height: AppSpacing.xxs),
                Wrap(
                  spacing: AppSpacing.xxs,
                  runSpacing: AppSpacing.xxs,
                  children: [
                    LocationBadge(candidate: candidate),
                    if (candidate.hasVideo) const VideoBadge(),
                  ],
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  experienceLabel(candidate.yearsExperience),
                  style: AppTypography.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (salary != null)
                  Text(
                    salary,
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
              ],
            ),
          ),
          FavouriteButton(
            candidateId: candidate.id,
            candidateTitle: candidate.title,
            size: 36,
          ),
        ],
      ),
    );
  }
}
