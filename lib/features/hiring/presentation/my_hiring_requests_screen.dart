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
import '../../../core/widgets/app_refresh_indicator.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/tab_screen.dart';
import '../../authentication/data/auth_providers.dart';
import '../../authentication/presentation/widgets/sign_in_prompt.dart';
import '../../visas/data/visa_repository.dart';
import '../../visas/domain/visa_application.dart';
import '../data/hiring_repository.dart';
import '../domain/hiring_request.dart';
import 'widgets/hiring_widgets.dart';

/// Requests tab: the customer's hiring requests, newest first.
class MyHiringRequestsScreen extends ConsumerWidget {
  const MyHiringRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user =
        ref.watch(authStateProvider).value ??
        ref.watch(authRepositoryProvider).currentUser;

    if (user == null) {
      return const TabScreen(
        title: 'Requests',
        child: SignInPrompt(
          icon: Icons.assignment_rounded,
          title: 'Sign in to see your requests',
          message: 'Follow your hiring requests and their visa progress in '
              'one place.',
        ),
      );
    }

    final requests = ref.watch(myHiringRequestsProvider);

    return TabScreen(
      title: 'Requests',
      scrollable: false,
      trailing: TextButton.icon(
        onPressed: () => unawaited(context.push(AppRoutes.hire())),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New'),
      ),
      child: requests.when(
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
          return AppRefreshIndicator(
            onRefresh: () async {
              ref
                ..invalidate(myHiringRequestsProvider)
                ..invalidate(myVisaApplicationsProvider);
              try {
                await ref.read(myHiringRequestsProvider.future);
              } on Object {
                // Shown in place of the list.
              }
            },
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                AppSpacing.xs,
                AppSpacing.screenPadding,
                AppSpacing.xl,
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

/// The visa application started for [request], if any.
VisaApplication? _visaFor(List<VisaApplication> visas, HiringRequest request) {
  for (final visa in visas) {
    if (visa.hiringRequestId == request.id) return visa;
  }
  return null;
}

class _RequestCard extends ConsumerWidget {
  const _RequestCard({required this.request});

  final HiringRequest request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visas = ref.watch(myVisaApplicationsProvider).value ?? const [];
    final visa = _visaFor(visas, request);

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
          if (visa != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () =>
                    unawaited(context.push(AppRoutes.visa(visa.id))),
                icon: const Icon(Icons.flight_takeoff_rounded, size: 18),
                label: const Text('Visa progress'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
