import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/errors/app_failure.dart';
import '../../../../core/routing/app_routes.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/app_button.dart';
import '../../../../core/widgets/app_card.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../../authentication/data/auth_providers.dart';
import '../../data/account_deletion_repository.dart';
import '../../domain/account_deletion.dart';

final DateFormat _requestDate = DateFormat('d MMMM yyyy');

/// Shown on Profile while a deletion request is waiting for the agency.
class PendingDeletionCard extends ConsumerWidget {
  const PendingDeletionCard({super.key});

  Future<void> _withdraw(
    BuildContext context,
    WidgetRef ref,
    AccountDeletionRequest request,
  ) async {
    try {
      await ref.read(accountDeletionRepositoryProvider).withdraw(request.id);
      if (!context.mounted) return;
      ref.invalidate(pendingDeletionProvider);
      showAppSnackBar(context, 'Request withdrawn. Your account stays open.');
    } on Object catch (error) {
      if (!context.mounted) return;
      // It may have been processed meanwhile.
      ref.invalidate(pendingDeletionProvider);
      showErrorSnackBar(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final request = ref.watch(pendingDeletionProvider).value;
    if (request == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: AppCard(
        color: AppColors.veryLightBlue,
        shadow: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.person_off_rounded, color: AppColors.error),
                SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Account deletion requested',
                    style: AppTypography.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'You asked us on '
              '${_requestDate.format(request.createdAt.toLocal())} to delete '
              'your account. Our team will process it. Changed your mind? '
              'Withdraw the request.',
              style: AppTypography.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.sm),
            AppButton(
              label: 'Withdraw request',
              variant: AppButtonVariant.outline,
              onPressed: () => _withdraw(context, ref, request),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Delete my account" at the bottom of Profile.
class DeleteAccountButton extends ConsumerWidget {
  const DeleteAccountButton({super.key});

  Future<void> _request(BuildContext context, WidgetRef ref) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const _DeleteAccountDialog(),
    );
    if (reason == null || !context.mounted) return;

    try {
      await ref
          .read(accountDeletionRepositoryProvider)
          .requestDeletion(reason: reason);
    } on Object catch (error) {
      if (context.mounted) showErrorSnackBar(context, error);
      return;
    }
    if (!context.mounted) return;
    ref.invalidate(pendingDeletionProvider);
    // The app-wide messenger keeps this visible after signing out.
    showAppSnackBar(
      context,
      'Your request was sent. Our team will delete your account.',
    );
    try {
      await ref.read(authRepositoryProvider).signOut();
      if (context.mounted) context.go(AppRoutes.welcome);
    } on AppFailure catch (failure) {
      if (context.mounted) showErrorSnackBar(context, failure);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Hidden while a request is pending (the card offers Withdraw instead).
    final pending = ref.watch(pendingDeletionProvider);
    if (pending.isLoading || pending.value != null) {
      return const SizedBox.shrink();
    }
    return Center(
      child: TextButton.icon(
        onPressed: () => _request(context, ref),
        style: TextButton.styleFrom(foregroundColor: AppColors.error),
        icon: const Icon(Icons.delete_outline_rounded),
        label: const Text('Delete my account'),
      ),
    );
  }
}

/// Explains what happens; returns the optional reason, or null to keep the
/// account.
class _DeleteAccountDialog extends StatefulWidget {
  const _DeleteAccountDialog();

  @override
  State<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<_DeleteAccountDialog> {
  final _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Delete your account?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Our team will delete your sign-in and personal details. Past '
              'bookings and hiring requests are kept for our records, without '
              'your name and contact details.\n\n'
              'You will be signed out now. If you change your mind, sign in '
              'again and withdraw the request before our team processes it.',
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _reason,
              maxLength: AccountDeletionRequest.maxReasonLength,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Why are you leaving? (optional)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Keep my account'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_reason.text.trim()),
          style: TextButton.styleFrom(foregroundColor: AppColors.error),
          child: const Text('Delete my account'),
        ),
      ],
    );
  }
}
