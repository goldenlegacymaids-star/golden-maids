import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_card.dart';
import '../../hiring/presentation/widgets/hiring_widgets.dart' show formatDay;
import '../domain/service_request.dart';

/// Coloured label for a request's status.
class ServiceRequestStatusBadge extends StatelessWidget {
  const ServiceRequestStatusBadge({super.key, required this.status});

  final ServiceRequestStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      ServiceRequestStatus.ready ||
      ServiceRequestStatus.completed => AppColors.success,
      ServiceRequestStatus.inProgress => AppColors.warning,
      ServiceRequestStatus.declined => AppColors.error,
      ServiceRequestStatus.cancelled => AppColors.textSecondary,
      ServiceRequestStatus.submitted => AppColors.primary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
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

/// Square icon for a request type (red for problems).
class ServiceRequestIcon extends StatelessWidget {
  const ServiceRequestIcon({super.key, required this.type, this.size = 40});

  final ServiceRequestType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    final problem = type == ServiceRequestType.problem;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: problem
            ? AppColors.error.withValues(alpha: 0.1)
            : AppColors.lightBlue,
        borderRadius: AppRadius.smAll,
      ),
      child: Icon(
        type.icon,
        size: size * 0.55,
        color: problem ? AppColors.error : AppColors.primary,
      ),
    );
  }
}

/// A request in the Requests tab.
class ServiceRequestCard extends StatelessWidget {
  const ServiceRequestCard({super.key, required this.request});

  final ServiceRequest request;

  @override
  Widget build(BuildContext context) {
    final maid = request.maidName.isNotEmpty
        ? request.maidName
        : request.hiringReference;
    return AppCard(
      onTap: () =>
          unawaited(context.push(AppRoutes.serviceRequest(request.id))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ServiceRequestIcon(type: request.type),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        request.type.label,
                        style: AppTypography.titleSmall,
                      ),
                    ),
                    ServiceRequestStatusBadge(status: request.status),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  [request.reference, ?maid].join(' · '),
                  style: AppTypography.bodySmall,
                ),
                Text(
                  'Sent ${formatDay(request.createdAt)}',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.textSecondary,
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

/// "New request": hiring a maid, then every other request type.
Future<void> showNewRequestSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    // Above the bottom navigation, so nothing is covered.
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) {
      void open(String location) {
        Navigator.of(sheetContext).pop();
        unawaited(context.push(location));
      }

      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              0,
              AppSpacing.screenPadding,
              AppSpacing.lg,
            ),
            children: [
              Semantics(
                header: true,
                child: const Text(
                  'What do you need?',
                  style: AppTypography.titleLarge,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              _SheetOption(
                icon: Icons.person_add_alt_1_rounded,
                label: 'Hire a maid',
                onTap: () => open(AppRoutes.hire()),
              ),
              for (final type in ServiceRequestType.values)
                _SheetOption(
                  icon: type.icon,
                  label: type.label,
                  isProblem: type == ServiceRequestType.problem,
                  onTap: () => open(AppRoutes.newServiceRequest(type.value)),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _SheetOption extends StatelessWidget {
  const _SheetOption({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isProblem = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isProblem;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: AppCard(
        bordered: true,
        shadow: false,
        onTap: onTap,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isProblem
                    ? AppColors.error.withValues(alpha: 0.1)
                    : AppColors.lightBlue,
                borderRadius: AppRadius.smAll,
              ),
              child: Icon(
                icon,
                size: 20,
                color: isProblem ? AppColors.error : AppColors.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(label, style: AppTypography.titleSmall)),
            const Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

/// A file on a request, opened with [onOpen].
class RequestFileTile extends StatelessWidget {
  const RequestFileTile({
    super.key,
    required this.file,
    required this.onOpen,
  });

  final ServiceRequestFile file;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final isPdf = file.fileName.toLowerCase().endsWith('.pdf');
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: AppCard(
        bordered: true,
        shadow: false,
        onTap: onOpen,
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Row(
          children: [
            Icon(
              isPdf ? Icons.picture_as_pdf_rounded : Icons.image_rounded,
              color: AppColors.primary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.displayName,
                    style: AppTypography.titleSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Added ${formatDay(file.createdAt)}',
                    style: AppTypography.bodySmall,
                  ),
                ],
              ),
            ),
            const Icon(Icons.open_in_new_rounded, size: 20),
          ],
        ),
      ),
    );
  }
}
