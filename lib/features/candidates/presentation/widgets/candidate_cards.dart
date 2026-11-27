import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radius.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_network_image.dart';
import '../../data/candidate_repository.dart';
import '../../domain/candidate.dart';
import '../maid_whatsapp.dart';
import '../open_candidate.dart';
import 'favourite_button.dart';
import 'nationality_flag.dart';

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
    this.fit = BoxFit.cover,
  });

  final String? url;

  /// Accessibility label, e.g. "Photo of Maria Santos".
  final String label;
  final double? width;
  final double? height;
  final BorderRadius borderRadius;
  final double iconSize;
  final BoxFit fit;

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
      fit: fit,
      // Maid photos are portrait: when cropped, keep the top (her face)
      // in view rather than the middle.
      alignment: Alignment.topCenter,
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
  /// Tall enough for a portrait photo to show the maid, not only her face.
  static const double photoHeight = 190;

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

/// "6 years", "1 year" or "New", as on the website's maid cards.
String cardExperience(int years) => switch (years) {
  0 => 'New',
  1 => '1 year',
  _ => '$years years',
};

/// Maid card for lists (Find a Maid, Saved Maids, search), laid out like the
/// website's phone card: photo on the left; name, job and nationality, four
/// facts, then Hire (in the app), View CV (the profile) and WhatsApp.
class CandidateListTile extends ConsumerWidget {
  const CandidateListTile({
    super.key,
    required this.candidate,
    required this.photoUrl,
    required this.onTap,
  });

  final Candidate candidate;
  final String? photoUrl;

  /// Opens the profile (the card itself and "View CV").
  final VoidCallback onTap;

  void _hire(BuildContext context, WidgetRef ref) {
    if (!isSignedIn(ref)) {
      showSignInSheet(context, title: 'Sign in to hire ${candidate.title}');
      return;
    }
    unawaited(context.push(AppRoutes.hire(candidateId: candidate.id)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salary = candidate.expectedSalary;
    final age = candidate.age;
    final inUae = candidate.location == MaidLocation.inUae;
    const photoRadius = BorderRadius.horizontal(
      left: Radius.circular(AppRadius.lg),
    );

    return AppCard(
      onTap: onTap,
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 38,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CandidatePhoto(
                      url: photoUrl,
                      label: 'Photo of ${candidate.title}',
                      iconSize: 40,
                      borderRadius: photoRadius,
                    ),
                  ),
                  if (candidate.hasVideo)
                    const Positioned(
                      left: AppSpacing.xs,
                      top: AppSpacing.xs,
                      child: _PlayBadge(),
                    ),
                  Positioned(
                    right: 2,
                    top: 2,
                    child: FavouriteButton(
                      candidateId: candidate.id,
                      candidateTitle: candidate.title,
                      size: 36,
                    ),
                  ),
                  Positioned(
                    left: AppSpacing.xs,
                    right: AppSpacing.xs,
                    bottom: AppSpacing.xs,
                    child: Wrap(
                      spacing: AppSpacing.xxs,
                      runSpacing: AppSpacing.xxs,
                      children: [
                        if (candidate.isTest) const TestTag(),
                        if (candidate.availability !=
                            CandidateAvailability.available)
                          AvailabilityBadge(
                            availability: candidate.availability,
                          ),
                        _Pill(
                          label: inUae ? 'In the UAE' : 'From abroad',
                          background: inUae
                              ? AppColors.successSoft
                              : AppColors.warningSoft,
                          foreground: inUae
                              ? AppColors.successText
                              : AppColors.warningText,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 62,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      candidate.title,
                      style: AppTypography.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            candidate.designation,
                            style: AppTypography.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        NationalityFlag(
                          nationality: candidate.nationality,
                          height: 12,
                        ),
                        const SizedBox(width: AppSpacing.xxs),
                        Flexible(
                          child: Text(
                            candidate.nationality,
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: _Fact(
                            label: 'Age',
                            value: age == null ? '—' : '$age years',
                          ),
                        ),
                        Expanded(
                          child: _Fact(
                            label: 'Experience',
                            value: cardExperience(candidate.yearsExperience),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Row(
                      children: [
                        Expanded(
                          child: _Fact(
                            label: 'Religion',
                            value: candidate.religion ?? '—',
                          ),
                        ),
                        Expanded(
                          child: _Fact(
                            label: 'Salary',
                            value: salary == null
                                ? '—'
                                : '${Formatters.aed(salary)} / mo',
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: AppSpacing.md),
                    Row(
                      children: [
                        Expanded(
                          child: AppButton(
                            label: 'Hire',
                            compact: true,
                            onPressed: () => _hire(context, ref),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: AppButton(
                            label: 'View CV',
                            variant: AppButtonVariant.outline,
                            compact: true,
                            onPressed: onTap,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    WhatsAppButton(
                      label: 'WhatsApp',
                      height: 38,
                      onPressed: () =>
                          unawaited(openHireWhatsApp(context, ref, candidate)),
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

/// One of the four facts on a maid card: a small label over the value.
class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.labelSmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: AppTypography.labelMedium.copyWith(
            color: AppColors.textPrimary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

/// Small rounded label on a coloured background.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.pillAll,
      ),
      child: Text(
        label,
        style: AppTypography.labelSmall.copyWith(color: foreground),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// White "play" badge on a card photo: the maid has a video interview.
class _PlayBadge extends StatelessWidget {
  const _PlayBadge();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Has a video interview',
      child: Container(
        width: 30,
        height: 22,
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: AppRadius.pillAll,
        ),
        child: const Icon(
          Icons.play_arrow_rounded,
          size: 16,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}
