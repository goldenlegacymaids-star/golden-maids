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
import '../../authentication/data/auth_providers.dart';
import '../../authentication/presentation/widgets/sign_in_prompt.dart';
import '../../visas/data/visa_repository.dart';
import '../../wallet/data/wallet_repository.dart';
import '../data/notification_repository.dart';
import '../domain/customer_notification.dart';

/// Home → bell: updates from the agency about the customer's
/// hiring requests and enquiries. Tapping one marks it read and opens it.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  Future<void> _markAllRead(BuildContext context, WidgetRef ref) async {
    ref.read(notificationReadsProvider.notifier).markAll();
    try {
      await ref.read(notificationRepositoryProvider).markRead();
    } on AppFailure catch (failure) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user =
        ref.watch(authStateProvider).value ??
        ref.watch(authRepositoryProvider).currentUser;
    final notifications = ref.watch(notificationListProvider);
    final unread = ref.watch(unreadNotificationCountProvider);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    if (user == null) {
      return const PageScaffold(
        title: 'Notifications',
        body: SingleChildScrollView(
          child: SignInPrompt(
            icon: Icons.notifications_none_rounded,
            title: 'Sign in to see updates',
            message:
                "We'll let you know here when your hiring "
                'requests are updated.',
          ),
        ),
      );
    }

    return PageScaffold(
      title: 'Notifications',
      trailing: unread == 0
          ? null
          : TextButton(
              onPressed: () => unawaited(_markAllRead(context, ref)),
              child: const Text('Mark all read'),
            ),
      body: notifications.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => SingleChildScrollView(
          child: ErrorState(
            failure: AppFailure.from(error),
            onRetry: () => ref.invalidate(customerNotificationsProvider),
          ),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const SingleChildScrollView(
              child: EmptyState(
                icon: Icons.notifications_none_rounded,
                title: 'No notifications yet',
                message:
                    "We'll let you know here when your hiring "
                    'requests are updated.',
              ),
            );
          }
          return ListView.separated(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              AppSpacing.xs,
              AppSpacing.screenPadding,
              bottomInset + AppSpacing.xl,
            ),
            itemCount: list.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) =>
                _NotificationCard(notification: list[index]),
          );
        },
      ),
    );
  }
}

class _NotificationCard extends ConsumerWidget {
  const _NotificationCard({required this.notification});

  final CustomerNotification notification;

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final n = notification;
    if (n.isUnread) {
      ref.read(notificationReadsProvider.notifier).add(n.id);
      // A failure only leaves it unread; opening still works.
      unawaited(
        ref
            .read(notificationRepositoryProvider)
            .markRead(ids: [n.id])
            .onError((_, _) {}),
      );
    }
    final requestId = n.hiringRequestId;
    final candidateId = n.candidateId;
    if (n.topic == NotificationTopic.document) {
      await context.push(AppRoutes.myDocuments);
    } else if (n.topic == NotificationTopic.visa && requestId != null) {
      // The visa page finds its application by the hiring request.
      ref.invalidate(myVisaApplicationsProvider);
      await context.push(AppRoutes.visa(requestId));
    } else if (n.topic == NotificationTopic.wallet) {
      ref.invalidate(walletOverviewProvider);
      context.go(AppRoutes.wallet);
    } else if (n.topic == NotificationTopic.booking) {
      // Home-service bookings are no longer offered: nothing to open.
      return;
    } else if (requestId != null) {
      context.go(AppRoutes.hiringRequest(requestId));
    } else if (candidateId != null) {
      await context.push(AppRoutes.candidate(candidateId));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = notification;
    final icon = switch (n.topic) {
      NotificationTopic.booking => Icons.calendar_today_rounded,
      NotificationTopic.hiring => Icons.assignment_ind_rounded,
      NotificationTopic.enquiry => Icons.chat_bubble_outline_rounded,
      NotificationTopic.document => Icons.folder_rounded,
      NotificationTopic.wallet => Icons.account_balance_wallet_rounded,
      NotificationTopic.visa => Icons.flight_rounded,
      NotificationTopic.other => Icons.notifications_none_rounded,
    };
    return Semantics(
      label: n.isUnread ? 'Unread' : null,
      child: AppCard(
        onTap: () => unawaited(_open(context, ref)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: AppColors.lightBlue,
              child: Icon(icon, size: 20, color: AppColors.primary),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          n.title,
                          style: n.isUnread
                              ? AppTypography.titleSmall
                              : AppTypography.bodyMedium,
                        ),
                      ),
                      if (n.isUnread) ...[
                        const SizedBox(width: AppSpacing.xs),
                        const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: CircleAvatar(
                            radius: 4,
                            backgroundColor: AppColors.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (n.body.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(n.body, style: AppTypography.bodySmall),
                  ],
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    notificationTime(n.createdAt),
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.textSecondary,
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
