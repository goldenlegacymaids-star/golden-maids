import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../candidates/presentation/open_candidate.dart';
import '../data/hiring_repository.dart';
import 'widgets/hiring_widgets.dart';

/// One hiring request: summary, status timeline and cancelling.
class HiringRequestScreen extends ConsumerWidget {
  const HiringRequestScreen({super.key, required this.requestId});

  final String requestId;

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this request?'),
        content: const Text(
          'The recruitment team will stop working on it. You can send a new '
          'request at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep request'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Cancel request'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(hiringRepositoryProvider).cancel(requestId);
      ref
        ..invalidate(hiringRequestProvider(requestId))
        ..invalidate(hiringHistoryProvider(requestId))
        ..invalidate(myHiringRequestsProvider);
      if (context.mounted) showAppSnackBar(context, 'Request cancelled.');
    } on Object catch (error) {
      if (context.mounted) showErrorSnackBar(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = ref.watch(hiringRequestProvider(requestId));

    return PageScaffold(
      title: request.value?.reference ?? 'Hiring request',
      body: request.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => SingleChildScrollView(
          child: ErrorState(
            failure: AppFailure.from(error),
            onRetry: () => ref.invalidate(hiringRequestProvider(requestId)),
          ),
        ),
        data: (data) {
          final bottomInset = MediaQuery.paddingOf(context).bottom;
          final household = [
            if (data.householdSize case final size?) '$size people',
            if (data.hasChildren) 'children',
            if (data.hasElderly) 'elderly',
            if (data.hasPets) 'pets',
          ];
          final candidate = data.candidate;

          return ListView(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              AppSpacing.xs,
              AppSpacing.screenPadding,
              bottomInset + AppSpacing.xl,
            ),
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text('Status', style: AppTypography.titleMedium),
                  ),
                  HiringStatusBadge(status: data.status),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              AppCard(
                onTap: candidate == null
                    ? null
                    : () => openCandidate(context, ref, candidate),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SummaryRow(label: 'Maid', value: data.maidLabel),
                    SummaryRow(label: 'Package', value: data.packageName),
                    SummaryRow(
                      label: 'Duration',
                      value: monthsLabel(data.durationMonths),
                    ),
                    if (data.sponsorNationality case final iso?)
                      SummaryRow(
                        label: "Sponsor's nationality",
                        value: gccCountryName(iso),
                      ),
                    SummaryRow(label: 'Emirate', value: data.emirate),
                    if (household.isNotEmpty)
                      SummaryRow(
                        label: 'Household',
                        value: household.join(', '),
                      ),
                    if (data.preferredStartDate case final date?)
                      SummaryRow(label: 'Start date', value: formatDay(date)),
                    if (data.requirements.isNotEmpty)
                      SummaryRow(
                        label: 'Requirements',
                        value: data.requirements,
                      ),
                    SummaryRow(
                      label: 'Contact by',
                      value: data.contactMethod.label,
                    ),
                    SummaryRow(
                      label: 'Sent',
                      value: formatDayTime(data.createdAt),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              const Text('Progress', style: AppTypography.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              _Timeline(requestId: requestId),
              if (data.status.canCancel) ...[
                const SizedBox(height: AppSpacing.xl),
                AppButton(
                  label: 'Cancel request',
                  variant: AppButtonVariant.outline,
                  onPressed: () => _cancel(context, ref),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _Timeline extends ConsumerWidget {
  const _Timeline({required this.requestId});

  final String requestId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(hiringHistoryProvider(requestId));

    return history.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => ErrorState(
        failure: AppFailure.from(error),
        onRetry: () => ref.invalidate(hiringHistoryProvider(requestId)),
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
                      color: AppColors.primary,
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
                          formatDayTime(event.createdAt),
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
