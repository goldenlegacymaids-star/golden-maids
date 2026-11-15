import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../data/hiring_repository.dart';
import '../domain/hiring_request.dart';
import 'widgets/hiring_widgets.dart';

/// Profile → My Hiring Requests.
class MyHiringRequestsScreen extends ConsumerWidget {
  const MyHiringRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requests = ref.watch(myHiringRequestsProvider);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return PageScaffold(
      title: 'My Hiring Requests',
      trailing: TextButton.icon(
        onPressed: () => unawaited(context.push(AppRoutes.hire())),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New'),
      ),
      body: requests.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => SingleChildScrollView(
          child: ErrorState(
            failure: AppFailure.from(error),
            onRetry: () => ref.invalidate(myHiringRequestsProvider),
          ),
        ),
        data: (list) {
          if (list.isEmpty) {
            return SingleChildScrollView(
              child: EmptyState(
                icon: Icons.assignment_ind_rounded,
                title: 'No hiring requests yet',
                message:
                    'Choose a maid and a package, and send us a request. '
                    'You can follow its progress here.',
                actionLabel: 'Find a Maid',
                onAction: () => context.go(AppRoutes.maids),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(myHiringRequestsProvider);
              try {
                await ref.read(myHiringRequestsProvider.future);
              } on Object {
                // Shown in place of the list.
              }
            },
            child: ListView.separated(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                AppSpacing.xs,
                AppSpacing.screenPadding,
                bottomInset + AppSpacing.xl,
              ),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, index) =>
                  _RequestCard(request: list[index]),
            ),
          );
        },
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request});

  final HiringRequest request;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: () =>
          unawaited(context.push(AppRoutes.hiringRequest(request.id))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(request.reference, style: AppTypography.titleSmall),
              ),
              HiringStatusBadge(status: request.status),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            request.maidLabel,
            style: AppTypography.bodyMedium,
          ),
          Text(
            '${request.packageName} · ${monthsLabel(request.durationMonths)}',
            style: AppTypography.bodySmall,
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Sent ${formatDay(request.createdAt)}',
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
