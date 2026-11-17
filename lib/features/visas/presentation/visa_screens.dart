import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/agency_contact.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_refresh_indicator.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../candidates/data/candidate_repository.dart';
import '../../candidates/presentation/candidate_profile_screen.dart'
    show openExternal;
import '../../candidates/presentation/widgets/candidate_cards.dart';
import '../../documents/data/document_repository.dart';
import '../../documents/domain/customer_document.dart';
import '../data/visa_repository.dart';
import '../domain/visa_application.dart';

final _day = DateFormat('d MMM yyyy');

DateTime _today() => DateTime.now();

/// The sponsor's documents still to send, or to send again.
List<DocumentType> missingSponsorDocuments(List<CustomerDocument> documents) {
  return [
    for (final type in DocumentType.values)
      if (!documents.any(
        (d) => d.type == type && d.status != DocumentStatus.needsNewCopy,
      ))
        type,
  ];
}

Future<void> _refresh(WidgetRef ref) async {
  ref
    ..invalidate(myVisaApplicationsProvider)
    ..invalidate(myDocumentsProvider);
  try {
    await ref.read(myVisaApplicationsProvider.future);
  } on Object {
    // Shown in place of the list.
  }
}

/// Profile → My Visa Applications: one card per visa the agency is
/// processing, with its progress.
class MyVisaApplicationsScreen extends ConsumerWidget {
  const MyVisaApplicationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final applications = ref.watch(myVisaApplicationsProvider);
    final documents =
        ref.watch(myDocumentsProvider).value ?? const <CustomerDocument>[];
    final missing = missingSponsorDocuments(documents).isNotEmpty;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return PageScaffold(
      title: 'My Visa Applications',
      body: applications.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => SingleChildScrollView(
          child: ErrorState(
            failure: AppFailure.from(error),
            onRetry: () => ref.invalidate(myVisaApplicationsProvider),
          ),
        ),
        data: (list) => AppRefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: list.isEmpty
              ? const SingleChildScrollView(
                  physics: AlwaysScrollableScrollPhysics(),
                  child: EmptyState(
                    icon: Icons.badge_outlined,
                    title: 'No visa applications yet',
                    message:
                        'When Golden Maids starts your maid’s visa, you can '
                        'follow each step here.',
                  ),
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.screenPadding,
                    AppSpacing.xs,
                    AppSpacing.screenPadding,
                    bottomInset + AppSpacing.xl,
                  ),
                  itemCount: list.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, index) => _VisaCard(
                    application: list[index],
                    missingDocuments: missing,
                  ),
                ),
        ),
      ),
    );
  }
}

class _VisaCard extends StatelessWidget {
  const _VisaCard({required this.application, required this.missingDocuments});

  final VisaApplication application;
  final bool missingDocuments;

  @override
  Widget build(BuildContext context) {
    final today = _today();
    final state = application.state(today, missingDocuments: missingDocuments);
    final total = application.steps.length;
    final current = application.currentStep;
    final days = application.daysToExpiry(today);
    final expires = application.expiresOn;

    final String line;
    if (state == VisaState.expiringSoon && expires != null) {
      line = (days ?? 0) < 0
          ? 'Expired on ${_day.format(expires)}'
          : 'Expires on ${_day.format(expires)}';
    } else if (state == VisaState.actionNeeded) {
      line = 'Please send your documents';
    } else if (expires != null) {
      line = 'Valid until ${_day.format(expires)}';
    } else if (current != null) {
      line = 'Step ${current.position} of $total · ${current.step.label}';
    } else {
      line = 'All steps done';
    }

    return AppCard(
      onTap: () => unawaited(context.push(AppRoutes.visa(application.id))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _MaidAvatar(application: application, size: 44),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _maidName(application),
                      style: AppTypography.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${_visaName(application)} · '
                      '${application.journey.label}',
                      style: AppTypography.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              VisaStateBadge(state: state),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ClipRRect(
            borderRadius: AppRadius.pillAll,
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : application.doneCount / total,
              minHeight: 6,
              backgroundColor: AppColors.border,
              color: AppColors.primary,
              // The value itself is read as a percentage.
              semanticsLabel:
                  'Visa progress: ${application.doneCount} of $total steps '
                  'done',
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(line, style: AppTypography.bodySmall),
        ],
      ),
    );
  }
}

String _maidName(VisaApplication application) =>
    application.candidate?.title ?? 'Your maid';

String _visaName(VisaApplication application) =>
    application.isSponsorVisa ? 'GCC Sponsor Visa' : 'Company Visa';

class _MaidAvatar extends ConsumerWidget {
  const _MaidAvatar({required this.application, required this.size});

  final VisaApplication application;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final candidate = application.candidate;
    return ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: CandidatePhoto(
          url: candidate == null
              ? null
              : ref
                    .watch(candidateRepositoryProvider)
                    .photoUrl(candidate.photoPath),
          label: 'Photo of ${_maidName(application)}',
          width: size,
          height: size,
          iconSize: size * 0.5,
        ),
      ),
    );
  }
}

/// In progress · Action needed · Visa ready · Expiring soon.
class VisaStateBadge extends StatelessWidget {
  const VisaStateBadge({super.key, required this.state});

  final VisaState state;

  @override
  Widget build(BuildContext context) {
    final (label, background, foreground) = switch (state) {
      VisaState.inProgress => (
        'In progress',
        AppColors.lightBlue,
        AppColors.infoText,
      ),
      VisaState.actionNeeded => (
        'Action needed',
        AppColors.warningSoft,
        AppColors.warningText,
      ),
      VisaState.ready => (
        'Visa ready',
        AppColors.successSoft,
        AppColors.successText,
      ),
      VisaState.expiringSoon => (
        'Expiring soon',
        AppColors.error.withValues(alpha: 0.1),
        AppColors.errorText,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadius.pillAll,
      ),
      child: Text(
        label,
        style: AppTypography.labelSmall.copyWith(color: foreground),
      ),
    );
  }
}

/// One visa: the steps, what the customer needs to do, the documents the
/// agency added, and a way to ask about it.
class VisaApplicationScreen extends ConsumerWidget {
  const VisaApplicationScreen({super.key, required this.id});

  /// The application's id (or its hiring request's, from a notification).
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final applications = ref.watch(myVisaApplicationsProvider);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return PageScaffold(
      title: 'Visa application',
      body: applications.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => SingleChildScrollView(
          child: ErrorState(
            failure: AppFailure.from(error),
            onRetry: () => ref.invalidate(myVisaApplicationsProvider),
          ),
        ),
        data: (list) {
          VisaApplication? application;
          for (final item in list) {
            if (item.id == id || item.hiringRequestId == id) application = item;
          }
          final found = application;
          if (found == null) {
            return const SingleChildScrollView(
              child: EmptyState(
                icon: Icons.badge_outlined,
                title: 'Visa application not found',
                message: 'It may have been closed. Pull down on My Visa '
                    'Applications to refresh.',
              ),
            );
          }
          return AppRefreshIndicator(
            onRefresh: () => _refresh(ref),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                AppSpacing.xs,
                AppSpacing.screenPadding,
                bottomInset + AppSpacing.xl,
              ),
              children: [
                _Header(application: found),
                if (found.isSponsorVisa && !found.isComplete) ...[
                  const SizedBox(height: AppSpacing.sm),
                  const _NeededFromYou(),
                ],
                const SizedBox(height: AppSpacing.md),
                const Text('Steps', style: AppTypography.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                _Steps(application: found),
                const SizedBox(height: AppSpacing.md),
                const Text('Visa documents', style: AppTypography.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                _Documents(application: found),
                const SizedBox(height: AppSpacing.lg),
                AppButton(
                  label: 'Ask about this visa',
                  icon: Icons.chat_rounded,
                  variant: AppButtonVariant.outline,
                  onPressed: () => openExternal(
                    context,
                    ref,
                    AgencyContact.whatsAppUri(
                      'Hello Golden Maids, I have a question about the visa '
                      'for ${found.reference}.',
                    ),
                    failureMessage:
                        'Could not open WhatsApp. Please message '
                        '${AgencyContact.phoneDisplay}.',
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.application});

  final VisaApplication application;

  @override
  Widget build(BuildContext context) {
    final expires = application.expiresOn;
    final days = application.daysToExpiry(_today());
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _MaidAvatar(application: application, size: 52),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _maidName(application),
                      style: AppTypography.titleMedium,
                    ),
                    Text(
                      'Ref. ${application.reference}',
                      style: AppTypography.bodySmall,
                    ),
                    Text(
                      '${_visaName(application)} · '
                      '${application.journey.label}',
                      style: AppTypography.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!application.isSponsorVisa) ...[
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Golden Maids is the sponsor: the agency handles this visa. '
              'You can follow each step here.',
              style: AppTypography.bodySmall,
            ),
          ],
          if (expires != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _Banner(
              soon: days != null && days <= 7,
              text: days != null && days < 0
                  ? 'The visa expired on ${_day.format(expires)}. Contact '
                        'Golden Maids to renew it.'
                  : days != null && days <= 7
                  ? 'The visa expires on ${_day.format(expires)}. Contact '
                        'Golden Maids to renew it.'
                  : 'Visa valid until ${_day.format(expires)}. We will '
                        'remind you 7 days before it expires.',
            ),
          ],
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.soon, required this.text});

  final bool soon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: soon ? AppColors.error.withValues(alpha: 0.1) : AppColors.successSoft,
        borderRadius: AppRadius.mdAll,
      ),
      child: Text(
        text,
        style: AppTypography.bodySmall.copyWith(
          color: soon ? AppColors.errorText : AppColors.successText,
        ),
      ),
    );
  }
}

/// GCC Sponsor Visa: the documents still to send, with a way to send them.
class _NeededFromYou extends ConsumerWidget {
  const _NeededFromYou();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final documents = ref.watch(myDocumentsProvider).value;
    if (documents == null) return const SizedBox.shrink();
    final missing = missingSponsorDocuments(documents);
    if (missing.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: const BoxDecoration(
        color: AppColors.warningSoft,
        borderRadius: AppRadius.mdAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Needed from you',
            style: AppTypography.titleSmall.copyWith(
              color: AppColors.warningText,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            missing.map((t) => t.label).join(' · '),
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.warningText,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () =>
                  unawaited(context.push(AppRoutes.myDocuments)),
              child: const Text('Send in My Documents'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.application});

  final VisaApplication application;

  @override
  Widget build(BuildContext context) {
    final steps = application.steps;
    final current = application.currentStep;
    return AppCard(
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++)
            _StepRow(
              progress: steps[i],
              isCurrent: identical(steps[i], current),
              isLast: i == steps.length - 1,
            ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.progress,
    required this.isCurrent,
    required this.isLast,
  });

  final VisaStepProgress progress;
  final bool isCurrent;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final done = progress.status == VisaStepStatus.done;
    final active = progress.status == VisaStepStatus.inProgress;
    final date = progress.date;
    final detail = [
      if (done) 'Done',
      if (active) 'In progress',
      if (!done && !active && isCurrent) 'Next',
      if (date != null) _day.format(date),
    ].join(' · ');

    return Semantics(
      label: '${progress.step.label}. ${detail.isEmpty ? 'Waiting' : detail}.'
          '${progress.note.isEmpty ? '' : ' ${progress.note}'}',
      excludeSemantics: true,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24,
              child: Column(
                children: [
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done
                          ? AppColors.success
                          : active
                          ? AppColors.primary
                          : AppColors.white,
                      border: done || active
                          ? null
                          : Border.all(color: AppColors.border, width: 2),
                    ),
                    child: done
                        ? const Icon(
                            Icons.check_rounded,
                            size: 14,
                            color: AppColors.white,
                          )
                        : null,
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 2,
                        color: done ? AppColors.success : AppColors.border,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      progress.step.label,
                      style: AppTypography.bodyMedium.copyWith(
                        color: done || active
                            ? AppColors.textPrimary
                            : AppColors.textSecondary,
                        fontWeight: active ? FontWeight.w600 : null,
                      ),
                    ),
                    if (detail.isNotEmpty)
                      Text(detail, style: AppTypography.bodySmall),
                    if (progress.note.isNotEmpty)
                      Text(progress.note, style: AppTypography.bodySmall),
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

class _Documents extends ConsumerWidget {
  const _Documents({required this.application});

  final VisaApplication application;

  Future<void> _view(
    BuildContext context,
    WidgetRef ref,
    VisaDocument document,
  ) async {
    try {
      final url = await ref.read(visaRepositoryProvider).viewUrl(document);
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
    final documents = application.documents;
    if (documents.isEmpty) {
      return const AppCard(
        child: Text(
          'Golden Maids will add the visa, contract and other documents '
          'here as they are issued.',
          style: AppTypography.bodySmall,
        ),
      );
    }
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Column(
        children: [
          for (var i = 0; i < documents.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            ListTile(
              leading: const Icon(
                Icons.description_outlined,
                color: AppColors.primary,
              ),
              title: Text(
                documents[i].displayName,
                style: AppTypography.bodyMedium,
              ),
              subtitle: Text(
                'Added ${_day.format(documents[i].createdAt.toLocal())}',
                style: AppTypography.bodySmall,
              ),
              trailing: TextButton(
                onPressed: () => _view(context, ref, documents[i]),
                child: const Text('View'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
