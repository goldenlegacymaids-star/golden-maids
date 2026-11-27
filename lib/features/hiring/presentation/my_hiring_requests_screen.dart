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
import '../../service_requests/data/service_request_repository.dart';
import '../../service_requests/presentation/service_request_widgets.dart';
import '../../visas/data/visa_repository.dart';
import '../../visas/domain/visa_application.dart';
import '../data/hiring_repository.dart';
import '../domain/hiring_request.dart';
import 'widgets/hiring_widgets.dart';

/// Requests tab: everything the customer asked for. Hiring requests, then
/// other requests (visa, replacement, NOC, …), newest first; "New" opens
/// the list of request types.
class MyHiringRequestsScreen extends ConsumerWidget {
  const MyHiringRequestsScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref
      ..invalidate(myHiringRequestsProvider)
      ..invalidate(myServiceRequestsProvider)
      ..invalidate(myVisaApplicationsProvider);
    try {
      await Future.wait([
        ref.read(myHiringRequestsProvider.future),
        ref.read(myServiceRequestsProvider.future),
      ]);
    } on Object {
      // Shown in place of the list.
    }
  }

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
          message: 'Hire a maid, ask for a visa, NOC or certificate, and '
              'follow every request in one place.',
        ),
      );
    }

    final hiring = ref.watch(myHiringRequestsProvider);
    final services = ref.watch(myServiceRequestsProvider);
    final error = hiring.hasValue
        ? (services.hasValue ? null : services.error)
        : hiring.error;

    return TabScreen(
      title: 'Requests',
      scrollable: false,
      trailing: TextButton.icon(
        onPressed: () => unawaited(showNewRequestSheet(context)),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New'),
      ),
      child: Builder(
        builder: (context) {
          if (error != null) {
            return SingleChildScrollView(
              child: ErrorState(
                failure: AppFailure.from(error),
                onRetry: () => unawaited(_refresh(ref)),
              ),
            );
          }
          final hires = hiring.value;
          final others = services.value;
          if (hires == null || others == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (hires.isEmpty && others.isEmpty) {
            return SingleChildScrollView(
              child: EmptyState(
                icon: Icons.assignment_ind_rounded,
                title: 'No requests yet',
                message:
                    'Hire a maid, or ask us for a visa, a travel NOC, a '
                    'certificate and more. You can follow each request here.',
                actionLabel: 'New request',
                onAction: () => unawaited(showNewRequestSheet(context)),
              ),
            );
          }
          return AppRefreshIndicator(
            onRefresh: () => _refresh(ref),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                AppSpacing.xs,
                AppSpacing.screenPadding,
                AppSpacing.xl,
              ),
              children: [
                if (hires.isNotEmpty) ...[
                  const _SectionTitle('Hiring'),
                  for (final request in hires) ...[
                    _RequestCard(request: request),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ],
                if (others.isNotEmpty) ...[
                  if (hires.isNotEmpty) const SizedBox(height: AppSpacing.xs),
                  const _SectionTitle('Other requests'),
                  for (final request in others) ...[
                    ServiceRequestCard(request: request),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Semantics(
        header: true,
        child: Text(text, style: AppTypography.titleMedium),
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
