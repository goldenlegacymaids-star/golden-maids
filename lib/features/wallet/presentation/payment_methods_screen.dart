import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../data/wallet_repository.dart';
import '../domain/wallet.dart';
import 'coming_soon_sheet.dart';

/// Profile → Payment Methods (also Wallet → My cards): the customer's saved
/// cards. Cards are added in the payment provider's secure form once it is
/// connected; only the brand, last 4 digits and expiry are kept.
class PaymentMethodsScreen extends ConsumerWidget {
  const PaymentMethodsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cards = ref.watch(savedCardsProvider);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return PageScaffold(
      title: 'Payment Methods',
      body: cards.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => SingleChildScrollView(
          child: ErrorState(
            failure: AppFailure.from(error),
            onRetry: () => ref.invalidate(savedCardsProvider),
          ),
        ),
        data: (list) => ListView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            AppSpacing.xs,
            AppSpacing.screenPadding,
            bottomInset + AppSpacing.xl,
          ),
          children: [
            if (list.isEmpty)
              const AppCard(
                child: Row(
                  children: [
                    Icon(Icons.credit_card_off_rounded, color: AppColors.primary),
                    SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'No saved cards yet.',
                        style: AppTypography.bodyMedium,
                      ),
                    ),
                  ],
                ),
              )
            else
              for (final card in list) ...[
                SavedCardTile(card: card),
                const SizedBox(height: AppSpacing.sm),
              ],
            const SizedBox(height: AppSpacing.md),
            AppButton(
              label: 'Add a card',
              icon: Icons.add_card_rounded,
              onPressed: () => showComingSoonSheet(
                context,
                title: 'Card payments are coming soon',
                message:
                    "You'll be able to save a Visa or Mastercard here and "
                    'pay for bookings, hiring fees and deposits in the app.',
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lock_rounded, size: 18, color: AppColors.infoText),
                SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    'Card details are entered in our payment provider’s '
                    'secure form. Golden Maids never sees or stores your full '
                    'card number: only the card type, the last 4 digits and '
                    'the expiry date are shown here.',
                    style: AppTypography.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A saved card with "Default" and actions.
class SavedCardTile extends ConsumerStatefulWidget {
  const SavedCardTile({super.key, required this.card});

  final SavedCard card;

  @override
  ConsumerState<SavedCardTile> createState() => _SavedCardTileState();
}

class _SavedCardTileState extends ConsumerState<SavedCardTile> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      ref.invalidate(savedCardsProvider);
      showAppSnackBar(context, done);
    } on Object catch (error) {
      if (mounted) showErrorSnackBar(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final card = widget.card;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${cardBrandLabel(card.brand)} •••• ${card.last4}?'),
        content: const Text('You can add it again later.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(
      () => ref.read(walletRepositoryProvider).removeCard(card.id),
      'Card removed.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final expired = card.isExpired(DateTime.now());
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 52,
            height: 36,
            decoration: const BoxDecoration(
              borderRadius: AppRadius.smAll,
              gradient: LinearGradient(
                colors: [Color(0xFF123E82), Color(0xFF2F7FE0)],
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              cardBrandLabel(card.brand).toUpperCase(),
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.white,
                fontWeight: FontWeight.w700,
                fontSize: 9,
              ),
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${cardBrandLabel(card.brand)} •••• ${card.last4}',
                  style: AppTypography.titleSmall,
                ),
                Text(
                  expired ? 'Expired' : card.expiryLabel,
                  style: AppTypography.bodySmall.copyWith(
                    color: expired ? AppColors.errorText : null,
                  ),
                ),
              ],
            ),
          ),
          if (card.isDefault)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: 3,
              ),
              decoration: const BoxDecoration(
                color: AppColors.successSoft,
                borderRadius: AppRadius.pillAll,
              ),
              child: Text(
                'Default',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.successText,
                ),
              ),
            ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.all(AppSpacing.xs),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            PopupMenuButton<String>(
              tooltip: 'Card options',
              onSelected: (value) {
                if (value == 'default') {
                  unawaited(
                    _run(
                      () => ref
                          .read(walletRepositoryProvider)
                          .setDefaultCard(card.id),
                      'Default card updated.',
                    ),
                  );
                } else {
                  unawaited(_remove());
                }
              },
              itemBuilder: (context) => [
                if (!card.isDefault)
                  const PopupMenuItem(
                    value: 'default',
                    child: Text('Make default'),
                  ),
                const PopupMenuItem(value: 'remove', child: Text('Remove')),
              ],
            ),
        ],
      ),
    );
  }
}
