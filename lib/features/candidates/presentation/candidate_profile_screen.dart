import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/agency_contact.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/services/external_launcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../data/candidate_repository.dart';
import '../domain/candidate.dart';
import '../domain/candidate_profile.dart';
import 'enquiry_sheet.dart';
import 'maid_whatsapp.dart';
import 'widgets/candidate_cards.dart';
import 'widgets/favourite_button.dart';
import 'widgets/video_interview.dart';

/// Opens [uri] in another app, or explains that it could not.
Future<void> openExternal(
  BuildContext context,
  WidgetRef ref,
  Uri uri, {
  required String failureMessage,
}) async {
  var opened = false;
  try {
    opened = await ref.read(externalLauncherProvider)(uri);
  } on Object {
    opened = false;
  }
  if (!opened && context.mounted) {
    showAppSnackBar(context, failureMessage, isError: true);
  }
}

/// Full candidate profile (signed-in users; guests are redirected to sign
/// in by the router).
class CandidateProfileScreen extends ConsumerWidget {
  const CandidateProfileScreen({super.key, required this.candidateId});

  final String candidateId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(candidateProfileProvider(candidateId));
    final title = profile.value?.candidate.title ?? 'Candidate';

    return PageScaffold(
      title: title,
      trailing: FavouriteButton(
        candidateId: candidateId,
        candidateTitle: title,
      ),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) {
          final failure = AppFailure.from(error);
          return SingleChildScrollView(
            child: ErrorState(
              failure: failure is NotFoundFailure
                  ? const NotFoundFailure(
                      message: 'This candidate is no longer listed. '
                          'Browse other available maids.',
                    )
                  : failure,
              onRetry: failure is NotFoundFailure
                  ? null
                  : () => ref.invalidate(candidateProfileProvider(candidateId)),
            ),
          );
        },
        data: (data) => _ProfileBody(profile: data),
      ),
    );
  }
}

/// Laid out like the website's maid page on a phone: photo, badges, name,
/// four key facts and the hire buttons, then a card per section.
class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.profile});

  final CandidateProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final candidate = profile.candidate;
    final repository = ref.watch(candidateRepositoryProvider);
    final inUae = candidate.location == MaidLocation.inUae;
    final age = candidate.age;
    final subtitle = [
      candidate.designation,
      candidate.nationality,
      if (age != null) '$age years',
    ].join(' · ');

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
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Photo(
                      candidate: candidate,
                      url: repository.photoUrl(candidate.photoPath),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        _Badge(
                          label: inUae ? 'In the UAE' : 'From abroad',
                          background: inUae
                              ? AppColors.successSoft
                              : AppColors.warningSoft,
                          foreground: inUae
                              ? AppColors.successText
                              : AppColors.warningText,
                        ),
                        _Badge(
                          label:
                              candidate.availability ==
                                  CandidateAvailability.available
                              ? 'Available now'
                              : candidate.availability.label,
                        ),
                        if (profile.videoId != null)
                          const _Badge(
                            label: 'Video interview',
                            icon: Icons.play_arrow_rounded,
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Semantics(
                      header: true,
                      child: Text(
                        '${candidate.title}, '
                        '${candidate.designation.toLowerCase()} from '
                        '${candidate.nationality}',
                        style: AppTypography.headlineSmall,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      subtitle,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _Facts(candidate: candidate),
                    const SizedBox(height: AppSpacing.sm),
                    _WhereSheIs(candidate: candidate),
                    const SizedBox(height: AppSpacing.md),
                    _HireActions(profile: profile),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'Maid code ${candidate.code}',
                      style: AppTypography.bodySmall,
                    ),
                  ],
                ),
              ),
              if (profile.videoId case final videoId?)
                _Section(
                  title: 'Video interview',
                  child: VideoInterview(videoId: videoId),
                ),
              if (profile.bio.isNotEmpty)
                _Section(
                  title: 'About',
                  child: Text(profile.bio, style: AppTypography.bodyMedium),
                ),
              if (profile.skills.isNotEmpty)
                _Section(
                  title: 'Skills',
                  child: Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (final skill in profile.skills)
                        _Badge(label: skill.label, icon: Icons.check_rounded),
                    ],
                  ),
                ),
              if (profile.languages.isNotEmpty)
                _Section(
                  title: 'Languages',
                  child: Column(
                    children: [
                      for (final language in profile.languages)
                        _LanguageRow(language: language),
                    ],
                  ),
                ),
              if (profile.experience.isNotEmpty)
                _Section(
                  title: 'Work history',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final job in profile.experience)
                        _ExperienceTile(job: job),
                    ],
                  ),
                ),
              _Section(
                title: 'Details',
                child: Column(children: _details(profile)),
              ),
              if (profile.packages.isNotEmpty)
                _Section(
                  title: 'Available for',
                  child: Column(
                    children: [
                      for (final package in profile.packages)
                        _PackageTile(
                          package: package,
                          nationality: profile.candidate.nationality,
                        ),
                    ],
                  ),
                ),
              if (profile.documents.isNotEmpty)
                _Section(
                  title: 'Documents',
                  child: Column(
                    children: [
                      for (final document in profile.documents)
                        _DocumentTile(document: document),
                    ],
                  ),
                ),
            ],
          ),
        ),
        _ContactBar(candidate: candidate),
      ],
    );
  }

  /// Job, Nationality, Age and Code (as on the website), then education,
  /// religion and marital status when known.
  List<Widget> _details(CandidateProfile profile) {
    final candidate = profile.candidate;
    final age = candidate.age;
    return [
      _InfoRow(label: 'Job', value: candidate.designation),
      _InfoRow(label: 'Nationality', value: candidate.nationality),
      if (age != null) _InfoRow(label: 'Age', value: '$age years'),
      _InfoRow(label: 'Code', value: candidate.code),
      if (profile.highestQualification case final value?)
        _InfoRow(label: 'Education', value: value),
      if (profile.religion case final value?)
        _InfoRow(label: 'Religion', value: value),
      if (profile.maritalStatus case final value?)
        _InfoRow(label: 'Marital status', value: value),
    ];
  }
}

/// A white card with a heading, like the website's profile sections.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(title, style: AppTypography.titleLarge),
            ),
            const SizedBox(height: AppSpacing.sm),
            child,
          ],
        ),
      ),
    );
  }
}

/// Rounded label (blue by default), optionally with an icon.
class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    this.icon,
    this.background = AppColors.lightBlue,
    this.foreground = AppColors.infoText,
  });

  final String label;
  final IconData? icon;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final leading = icon;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs + 2,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.pillAll,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leading != null) ...[
            Icon(leading, size: 16, color: foreground),
            const SizedBox(width: AppSpacing.xxs),
          ],
          Flexible(
            child: Text(
              label,
              style: AppTypography.labelMedium.copyWith(color: foreground),
            ),
          ),
        ],
      ),
    );
  }
}

/// A language with its level in a coloured label (fluent green, basic
/// amber, good blue), as on the website.
class _LanguageRow extends StatelessWidget {
  const _LanguageRow({required this.language});

  final CandidateLanguage language;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (language.proficiency) {
      'fluent' => (AppColors.successSoft, AppColors.successText),
      'basic' => (AppColors.warningSoft, AppColors.warningText),
      _ => (AppColors.lightBlue, AppColors.infoText),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: AppCard(
        bordered: true,
        shadow: false,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(language.language, style: AppTypography.bodyLarge),
            ),
            _Badge(
              label: language.proficiencyLabel,
              background: background,
              foreground: foreground,
            ),
          ],
        ),
      ),
    );
  }
}

/// Hire in the app (a hiring request) or on WhatsApp.
class _HireActions extends ConsumerWidget {
  const _HireActions({required this.profile});

  final CandidateProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final candidate = profile.candidate;
    final canHire =
        candidate.availability == CandidateAvailability.available &&
        profile.packages.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (canHire)
          AppButton(
            label: 'Hire ${candidate.title}',
            icon: Icons.assignment_ind_rounded,
            onPressed: () => unawaited(
              context.push(AppRoutes.hire(candidateId: candidate.id)),
            ),
          )
        else
          Text(
            '${candidate.title} is '
            '${candidate.availability.label.toLowerCase()} at the moment. '
            'Message us and we will suggest someone similar.',
            style: AppTypography.bodySmall,
          ),
        const SizedBox(height: AppSpacing.xs),
        WhatsAppButton(
          label: 'Hire on WhatsApp',
          onPressed: () => unawaited(openHireWhatsApp(context, ref, candidate)),
        ),
        if (canHire) ...[
          const SizedBox(height: AppSpacing.xs),
          const Text(
            'Hire sends a request in the app: choose a package, no payment '
            'is taken now. You can follow it in Requests.',
            style: AppTypography.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _Photo extends StatelessWidget {
  const _Photo({required this.candidate, required this.url});

  final Candidate candidate;
  final String? url;

  @override
  Widget build(BuildContext context) {
    final photo = url;
    return Stack(
      children: [
        if (photo == null)
          CandidatePhoto(
            url: null,
            label: 'Photo of ${candidate.title}',
            width: double.infinity,
            height: 340,
            iconSize: 96,
            borderRadius: AppRadius.lgAll,
          )
        else
          // The whole photo, never cropped, over a soft blurred copy of it.
          ClipRRect(
            borderRadius: AppRadius.lgAll,
            child: SizedBox(
              width: double.infinity,
              height: 340,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ExcludeSemantics(
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                      child: CandidatePhoto(url: photo, label: ''),
                    ),
                  ),
                  const ColoredBox(color: Color(0x14000000)),
                  CandidatePhoto(
                    url: photo,
                    label: 'Photo of ${candidate.title}',
                    fit: BoxFit.contain,
                  ),
                ],
              ),
            ),
          ),
        if (candidate.isTest)
          const Positioned(
            right: AppSpacing.sm,
            top: AppSpacing.sm,
            child: TestTag(),
          ),
      ],
    );
  }
}

/// Four key facts in soft tiles, as on the website: experience, expected
/// salary, accommodation and where she is.
class _Facts extends StatelessWidget {
  const _Facts({required this.candidate});

  final Candidate candidate;

  @override
  Widget build(BuildContext context) {
    final salary = candidate.expectedSalary;
    final facts = <(String, String)>[
      ('Experience', cardExperience(candidate.yearsExperience)),
      (
        'Expected salary',
        salary == null ? '—' : '${Formatters.aed(salary)} / mo',
      ),
      (
        'Accommodation',
        candidate.accommodation == 'live_out' ? 'Live-out' : 'Live-in',
      ),
      (
        'Where she is',
        candidate.location == MaidLocation.inUae ? 'In the UAE' : 'From abroad',
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - AppSpacing.sm) / 2;
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final (label, value) in facts)
              Container(
                width: width,
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: const BoxDecoration(
                  color: AppColors.veryLightBlue,
                  borderRadius: AppRadius.mdAll,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: AppTypography.labelSmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: AppTypography.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Flexible(
            child: Text(
              value,
              style: AppTypography.titleSmall,
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExperienceTile extends StatelessWidget {
  const _ExperienceTile({required this.job});

  final CandidateExperience job;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Icon(Icons.circle, size: 10, color: AppColors.primary),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${job.role} · ${job.country}',
                  style: AppTypography.titleSmall,
                ),
                Text(job.period, style: AppTypography.bodySmall),
                if (job.description.isNotEmpty)
                  Text(job.description, style: AppTypography.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PackageTile extends StatelessWidget {
  const _PackageTile({required this.package, required this.nationality});

  final RecruitmentPackage package;

  /// The maid's nationality (some packages are priced by nationality).
  final String nationality;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: AppCard(
        bordered: true,
        shadow: false,
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          children: [
            Icon(
              package.visaType == 'sponsor'
                  ? Icons.verified_user_rounded
                  : Icons.badge_rounded,
              color: AppColors.primary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(package.name, style: AppTypography.titleSmall),
                  if (package.description.isNotEmpty)
                    Text(package.description, style: AppTypography.bodySmall),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    packagePriceLabel(package, nationality: nationality),
                    style: AppTypography.labelMedium.copyWith(
                      color: AppColors.primary,
                    ),
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

class _DocumentTile extends ConsumerWidget {
  const _DocumentTile({required this.document});

  final CandidateDocument document;

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    try {
      final url = await ref
          .read(candidateRepositoryProvider)
          .documentUrl(document.storagePath);
      if (!context.mounted) return;
      await openExternal(
        context,
        ref,
        Uri.parse(url),
        failureMessage: "This document couldn't be opened.",
      );
    } on Object catch (error) {
      if (context.mounted) showErrorSnackBar(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: AppCard(
        bordered: true,
        shadow: false,
        padding: const EdgeInsets.all(AppSpacing.sm),
        onTap: () => unawaited(_open(context, ref)),
        child: Row(
          children: [
            const Icon(Icons.description_rounded, color: AppColors.primary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(document.title, style: AppTypography.titleSmall),
            ),
            const Icon(
              Icons.open_in_new_rounded,
              size: 18,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

/// Call, WhatsApp, Email and Request Info, always visible at the bottom.
class _ContactBar extends ConsumerWidget {
  const _ContactBar({required this.candidate});

  final Candidate candidate;

  Future<void> _requestInfo(BuildContext context) async {
    final reference = await showEnquirySheet(context, candidate: candidate);
    if (reference != null && context.mounted) {
      showAppSnackBar(
        context,
        "Enquiry sent ($reference). We'll contact you soon.",
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final about = 'Enquiry about ${candidate.code}';

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.white,
        boxShadow: AppShadows.soft,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            AppSpacing.sm,
            AppSpacing.screenPadding,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              AppIconButton(
                icon: Icons.call_rounded,
                tooltip: 'Call ${AgencyContact.phoneDisplay}',
                onPressed: () => unawaited(
                  openExternal(
                    context,
                    ref,
                    AgencyContact.callUri(),
                    failureMessage:
                        'Calls are not available on this device. Please '
                        'call ${AgencyContact.phoneDisplay}.',
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              AppIconButton(
                icon: Icons.chat_rounded,
                tooltip: 'WhatsApp',
                onPressed: () => unawaited(
                  openExternal(
                    context,
                    ref,
                    AgencyContact.whatsAppUri(
                      enquiryWhatsAppMessage(candidate),
                    ),
                    failureMessage: "WhatsApp couldn't be opened.",
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              AppIconButton(
                icon: Icons.mail_rounded,
                tooltip: 'Email',
                onPressed: () => unawaited(
                  openExternal(
                    context,
                    ref,
                    AgencyContact.emailUri(about),
                    failureMessage:
                        'No email app found. Please write to '
                        '${AgencyContact.email}.',
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AppButton(
                  label: 'Request Info',
                  // Not awaited: the button should not spin while the
                  // form is open.
                  onPressed: () => unawaited(_requestInfo(context)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Where the maid is now and when she can start.
class _WhereSheIs extends ConsumerWidget {
  const _WhereSheIs({required this.candidate});

  final Candidate candidate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inUae = candidate.location == MaidLocation.inUae;
    final arrival = arrivalFor(ref, candidate.nationality);
    final status = locationLabel(candidate, arrival: arrival);
    final detail = inUae
        ? switch (status) {
            'In the UAE · Available now' => 'Available now.',
            'In the UAE' => 'Ask the agency when she can start.',
            _ => 'Can start ${status.replaceFirst('In the UAE · From ', 'from ')}.',
          }
        : arrival == null
        ? 'Arrival time on request. The agency will confirm it with you.'
        : 'Expected to arrive in $arrival after you confirm.';
    final color = inUae ? AppColors.successText : AppColors.infoText;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: inUae ? AppColors.successSoft : AppColors.lightBlue,
        borderRadius: AppRadius.mdAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            inUae ? Icons.home_work_rounded : Icons.flight_land_rounded,
            color: color,
            size: 22,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  candidate.location.label,
                  style: AppTypography.titleSmall.copyWith(color: color),
                ),
                const SizedBox(height: 2),
                Text(detail, style: AppTypography.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
