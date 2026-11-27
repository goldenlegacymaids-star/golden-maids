import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_refresh_indicator.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/tab_screen.dart';
import '../../authentication/data/auth_providers.dart';
import '../../authentication/presentation/widgets/sign_in_prompt.dart';
import '../../billing/data/billing_repository.dart';
import '../../billing/domain/billing_document.dart';
import '../../candidates/presentation/candidate_profile_screen.dart'
    show openExternal;
import '../../hiring/presentation/widgets/hiring_widgets.dart' show formatDay;
import '../data/wallet_repository.dart';
import '../domain/wallet.dart';
import 'coming_soon_sheet.dart';

final _money = NumberFormat('#,##0.00', 'en_US');

/// "AED 1,250.00".
String walletAmount(double amount) => 'AED ${_money.format(amount)}';

/// Wallet tab: balance, cards and the history of payments, refunds and
/// credits. Card payments and top-ups open once the payment gateway is
/// connected (remote switches); until then their buttons explain this.
class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref
      ..invalidate(walletOverviewProvider)
      ..invalidate(walletSwitchesProvider)
      ..invalidate(savedCardsProvider)
      ..invalidate(myBillingDocumentsProvider);
    try {
      await ref.read(walletOverviewProvider.future);
    } on Object {
      // Shown in place of the wallet.
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user =
        ref.watch(authStateProvider).value ??
        ref.watch(authRepositoryProvider).currentUser;

    if (user == null) {
      return const TabScreen(
        title: 'Wallet',
        child: SignInPrompt(
          icon: Icons.account_balance_wallet_rounded,
          title: 'Sign in to use your wallet',
          message:
              'See your payments, refunds and credits, and save cards for '
              'quicker payment.',
        ),
      );
    }

    final overview = ref.watch(walletOverviewProvider);
    final switches =
        ref.watch(walletSwitchesProvider).value ?? const WalletSwitches();

    return TabScreen(
      title: 'Wallet',
      scrollable: false,
      child: overview.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => SingleChildScrollView(
          child: ErrorState(
            failure: AppFailure.from(error),
            onRetry: () => unawaited(_refresh(ref)),
          ),
        ),
        data: (data) => AppRefreshIndicator(
          onRefresh: () => _refresh(ref),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              0,
              AppSpacing.screenPadding,
              AppSpacing.xl,
            ),
            children: [
              _BalanceCard(
                balance: data?.balance ?? 0,
                switches: switches,
              ),
              const SizedBox(height: AppSpacing.lg),
              const _BillingSection(),
              const Text('Activity', style: AppTypography.titleMedium),
              const SizedBox(height: AppSpacing.sm),
              ..._history(data?.history ?? const []),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _history(List<WalletTransaction> history) {
    if (history.isEmpty) {
      return const [
        AppCard(
          child: Row(
            children: [
              Icon(Icons.receipt_long_rounded, color: AppColors.primary),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'No activity yet. Payments, refunds and credits will '
                  'appear here.',
                  style: AppTypography.bodySmall,
                ),
              ),
            ],
          ),
        ),
      ];
    }
    final widgets = <Widget>[];
    String? month;
    for (final entry in history) {
      final heading = walletMonth(entry.createdAt);
      if (heading != month) {
        month = heading;
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.xs,
              bottom: AppSpacing.xs,
            ),
            child: Text(
              heading,
              style: AppTypography.labelMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        );
      }
      widgets
        ..add(WalletEntryTile(entry: entry))
        ..add(const SizedBox(height: AppSpacing.xs));
    }
    return widgets;
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.balance, required this.switches});

  final double balance;
  final WalletSwitches switches;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: const BoxDecoration(
        borderRadius: AppRadius.xlAll,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF123E82), Color(0xFF2F7FE0)],
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0x332F7FE0),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_rounded,
                color: AppColors.white,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                'Wallet balance',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Semantics(
            label: 'Wallet balance ${walletAmount(balance)}',
            excludeSemantics: true,
            child: Text(
              walletAmount(balance),
              style: AppTypography.headlineLarge.copyWith(
                color: AppColors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Use it for hiring fees and monthly maid payments.',
            style: AppTypography.bodySmall.copyWith(color: AppColors.white),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _CardButton(
                  icon: Icons.add_rounded,
                  label: 'Add money',
                  filled: true,
                  onTap: () => unawaited(
                    showComingSoonSheet(
                      context,
                      title: switches.topUpEnabled && switches.cardPaymentsEnabled
                          ? 'Top-ups open soon'
                          : 'Top-ups are coming soon',
                      message:
                          "You'll be able to add money to your wallet by "
                          'card (Visa, Mastercard) and use it for hiring '
                          'fees and monthly maid payments.',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _CardButton(
                  icon: Icons.credit_card_rounded,
                  label: 'My cards',
                  filled: false,
                  onTap: () =>
                      unawaited(context.push(AppRoutes.paymentMethods)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CardButton extends StatelessWidget {
  const _CardButton({
    required this.icon,
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = filled ? const Color(0xFF123E82) : AppColors.white;
    return Material(
      color: filled ? AppColors.white : AppColors.white.withValues(alpha: 0.16),
      shape: StadiumBorder(
        side: filled
            ? BorderSide.none
            : BorderSide(color: AppColors.white.withValues(alpha: 0.7)),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 46),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: foreground),
              const SizedBox(width: 6),
              Text(
                label,
                style: AppTypography.labelLarge.copyWith(color: foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One line of the wallet history.
class WalletEntryTile extends StatelessWidget {
  const WalletEntryTile({super.key, required this.entry});

  final WalletTransaction entry;

  @override
  Widget build(BuildContext context) {
    final (icon, tint) = switch (entry.kind) {
      WalletKind.topUp => (Icons.add_card_rounded, AppColors.primary),
      WalletKind.payment => (Icons.receipt_long_rounded, AppColors.primary),
      WalletKind.refund => (Icons.undo_rounded, AppColors.successText),
      WalletKind.credit => (Icons.card_giftcard_rounded, AppColors.successText),
      WalletKind.adjustment => (Icons.tune_rounded, AppColors.textSecondary),
    };
    final effect = entry.balanceEffect;
    final amountText = effect > 0
        ? '+${walletAmount(entry.amount)}'
        : effect < 0
        ? '−${walletAmount(entry.amount)}'
        : walletAmount(entry.amount);
    final amountColor = entry.isIncoming
        ? AppColors.successText
        : AppColors.textPrimary;
    final settled = entry.status == WalletStatus.completed;

    return AppCard(
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: tint.withValues(alpha: 0.12),
            child: Icon(icon, color: tint, size: 20),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.description.isEmpty
                      ? entry.kind.label
                      : entry.description,
                  style: AppTypography.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${entry.kind.label} · ${entry.methodLabel}',
                  style: AppTypography.bodySmall,
                ),
                Text(
                  '${walletTime(entry.createdAt)} · ${entry.reference}',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amountText,
                style: AppTypography.titleSmall.copyWith(
                  color: settled ? amountColor : AppColors.textSecondary,
                  decoration: entry.status == WalletStatus.failed ||
                          entry.status == WalletStatus.cancelled
                      ? TextDecoration.lineThrough
                      : null,
                ),
              ),
              if (!settled)
                Text(
                  entry.status.label,
                  style: AppTypography.labelSmall.copyWith(
                    color: entry.status == WalletStatus.pending
                        ? AppColors.infoText
                        : AppColors.errorText,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Receipts and invoices the agency added; each opens its file.
class _BillingSection extends ConsumerWidget {
  const _BillingSection();

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    BillingDocument document,
  ) async {
    try {
      final url = await ref.read(billingRepositoryProvider).fileUrl(document);
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
    final documents = ref.watch(myBillingDocumentsProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Receipts and invoices',
            style: AppTypography.titleMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          documents.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.sm),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (error, _) => Text(
              AppFailure.from(error).message,
              style: AppTypography.bodySmall,
            ),
            data: (list) {
              if (list.isEmpty) {
                return const Text(
                  'Receipts and invoices from the agency will appear here.',
                  style: AppTypography.bodySmall,
                );
              }
              return Column(
                children: [
                  for (final document in list)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                      child: BillingDocumentTile(
                        document: document,
                        onOpen: () =>
                            unawaited(_open(context, ref, document)),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

/// A receipt or invoice: number, amount, date and (invoices) status.
class BillingDocumentTile extends StatelessWidget {
  const BillingDocumentTile({
    super.key,
    required this.document,
    required this.onOpen,
  });

  final BillingDocument document;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final status = document.status;
    final due = document.dueOn;
    final statusColor = switch (status) {
      InvoiceStatus.paid => AppColors.successText,
      InvoiceStatus.unpaid => AppColors.warningText,
      _ => AppColors.textSecondary,
    };
    return AppCard(
      onTap: onOpen,
      child: Row(
        children: [
          const CircleAvatar(
            radius: 20,
            backgroundColor: AppColors.lightBlue,
            child: Icon(
              Icons.receipt_long_rounded,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${document.kind.label} ${document.number}',
                  style: AppTypography.titleSmall,
                ),
                Text(
                  [
                    if (document.description.isNotEmpty) document.description,
                    'Issued ${formatDay(document.issuedOn)}',
                    if (due != null) 'Due ${formatDay(due)}',
                  ].join(' · '),
                  style: AppTypography.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                walletAmount(document.amount),
                style: AppTypography.titleSmall,
              ),
              if (status != null)
                Text(
                  status.label,
                  style: AppTypography.labelSmall.copyWith(color: statusColor),
                )
              else
                const Icon(
                  Icons.download_rounded,
                  size: 18,
                  color: AppColors.primary,
                ),
            ],
          ),
        ],
      ),
    );
  }
}
