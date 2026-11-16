import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

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
import '../../../core/widgets/app_chip.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../data/candidate_repository.dart';
import '../domain/candidate.dart';
import '../domain/candidate_profile.dart';
import 'enquiry_sheet.dart';
import 'widgets/candidate_cards.dart';
import 'widgets/favourite_button.dart';
import 'widgets/nationality_flag.dart';

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

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.profile});

  final CandidateProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final candidate = profile.candidate;
    final repository = ref.watch(candidateRepositoryProvider);

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
              _Photo(
                candidate: candidate,
                url: repository.photoUrl(candidate.photoPath),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(candidate.title, style: AppTypography.headlineSmall),
              Text(
                candidateSubtitle(candidate),
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              if (candidate.displayName != null)
                Text(
                  'Ref. ${candidate.code}',
                  style: AppTypography.bodySmall,
                ),
              const SizedBox(height: AppSpacing.md),
              _Facts(candidate: candidate),
              const SizedBox(height: AppSpacing.sm),
              _WhereSheIs(candidate: candidate),
              if (profile.bio.isNotEmpty) ...[
                const _Heading('About'),
                Text(profile.bio, style: AppTypography.bodyMedium),
              ],
              ..._details(profile),
              if (profile.skills.isNotEmpty) ...[
                const _Heading('Skills'),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    for (final skill in profile.skills)
                      AppChip(label: skill.label, selected: false, onTap: null),
                  ],
                ),
              ],
              if (profile.languages.isNotEmpty) ...[
                const _Heading('Languages'),
                for (final language in profile.languages)
                  _InfoRow(
                    label: language.language,
                    value: language.proficiencyLabel,
                  ),
              ],
              if (profile.experience.isNotEmpty) ...[
                const _Heading('Work history'),
                for (final job in profile.experience) _ExperienceTile(job: job),
              ],
              if (profile.packages.isNotEmpty) ...[
                const _Heading('Available for'),
                for (final package in profile.packages)
                  _PackageTile(
                    package: package,
                    nationality: profile.candidate.nationality,
                  ),
              ],
              if (profile.documents.isNotEmpty) ...[
                const _Heading('Documents'),
                for (final document in profile.documents)
                  _DocumentTile(document: document),
              ],
              const SizedBox(height: AppSpacing.lg),
              _HireCard(profile: profile),
            ],
          ),
        ),
        _ContactBar(candidate: candidate),
      ],
    );
  }

  List<Widget> _details(CandidateProfile profile) {
    final rows = [
      if (profile.highestQualification case final value?)
        _InfoRow(label: 'Education', value: value),
      if (profile.religion case final value?)
        _InfoRow(label: 'Religion', value: value),
      if (profile.maritalStatus case final value?)
        _InfoRow(label: 'Marital status', value: value),
    ];
    return rows.isEmpty ? const [] : [const _Heading('Details'), ...rows];
  }
}

class _Photo extends StatelessWidget {
  const _Photo({required this.candidate, required this.url});

  final Candidate candidate;
  final String? url;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        CandidatePhoto(
          url: url,
          label: 'Photo of ${candidate.title}',
          width: double.infinity,
          height: 300,
          iconSize: 96,
          borderRadius: AppRadius.xlAll,
        ),
        Positioned(
          left: AppSpacing.sm,
          top: AppSpacing.sm,
          child: AvailabilityBadge(availability: candidate.availability),
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

class _Facts extends StatelessWidget {
  const _Facts({required this.candidate});

  final Candidate candidate;

  static final DateFormat _date = DateFormat('d MMM yyyy');

  String _availableFrom() {
    final date = candidate.availableFrom;
    final today = DateUtils.dateOnly(DateTime.now());
    if (date == null || !date.isAfter(today)) return 'Now';
    return _date.format(date);
  }

  @override
  Widget build(BuildContext context) {
    final salary = candidate.expectedSalary;
    final age = candidate.age;
    Widget icon(IconData data) =>
        Icon(data, size: 20, color: AppColors.primary);
    final facts = <(Widget, String, String)>[
      (
        NationalityFlag(nationality: candidate.nationality, height: 16),
        'Nationality',
        candidate.nationality,
      ),
      if (age != null) (icon(Icons.cake_rounded), 'Age', '$age years'),
      (
        icon(Icons.work_history_rounded),
        'Experience',
        candidate.yearsExperience == 0
            ? 'None'
            : '${candidate.yearsExperience} '
                  '${candidate.yearsExperience == 1 ? 'year' : 'years'}',
      ),
      (
        icon(Icons.home_rounded),
        'Accommodation',
        candidate.accommodation == 'live_out' ? 'Live-out' : 'Live-in',
      ),
      (
        icon(Icons.event_available_rounded),
        'Available from',
        _availableFrom(),
      ),
      if (salary != null)
        (
          icon(Icons.payments_rounded),
          'Expected salary',
          Formatters.aed(salary),
        ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - AppSpacing.sm) / 2;
        return Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final (leading, label, value) in facts)
              SizedBox(
                width: width,
                child: AppCard(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Row(
                    children: [
                      SizedBox(width: 24, child: Center(child: leading)),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(label, style: AppTypography.labelSmall),
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
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl, bottom: AppSpacing.xs),
      child: Semantics(
        header: true,
        child: Text(text, style: AppTypography.titleMedium),
      ),
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

class _HireCard extends StatelessWidget {
  const _HireCard({required this.profile});

  final CandidateProfile profile;

  @override
  Widget build(BuildContext context) {
    final candidate = profile.candidate;
    final canHire =
        candidate.availability == CandidateAvailability.available &&
        profile.packages.isNotEmpty;

    return AppCard(
      color: AppColors.lightBlue,
      shadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Hire this maid', style: AppTypography.titleMedium),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            canHire
                ? 'Choose a package and send a hiring request. No payment '
                      'is taken now.'
                : '${candidate.title} is ${candidate.availability.label.toLowerCase()} '
                      'at the moment. Send a request below and we will '
                      'suggest someone similar.',
            style: AppTypography.bodySmall,
          ),
          if (canHire) ...[
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              label: 'Hire ${candidate.title}',
              icon: Icons.assignment_ind_rounded,
              onPressed: () => unawaited(
                context.push(AppRoutes.hire(candidateId: candidate.id)),
              ),
            ),
          ],
        ],
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
                      "Hello, I'm interested in ${candidate.code}.",
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
