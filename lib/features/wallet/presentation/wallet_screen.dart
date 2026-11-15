import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/tab_screen.dart';
import '../../authentication/data/auth_providers.dart';
import '../../authentication/presentation/widgets/sign_in_prompt.dart';

/// Wallet tab. The wallet, top-ups and payments are built in Phase 5.
///
/// No balance is shown until it comes from the backend: the app never
/// displays an amount it has not verified.
class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user =
        ref.watch(authStateProvider).value ??
        ref.watch(authRepositoryProvider).currentUser;

    return TabScreen(
      title: 'Wallet',
      child: user == null
          ? const SignInPrompt(
              icon: Icons.account_balance_wallet_rounded,
              title: 'Sign in to use your wallet',
              message: 'Pay for services, receive refunds and use credits '
                  'with your Golden Maids wallet.',
            )
          : const EmptyState(
              icon: Icons.account_balance_wallet_rounded,
              title: 'Wallet coming soon',
              message: 'Top up, pay for services and track refunds, '
                  'promotional credits and gift cards here.',
            ),
    );
  }
}
