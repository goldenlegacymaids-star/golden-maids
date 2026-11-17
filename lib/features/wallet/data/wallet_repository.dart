import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/supabase_providers.dart';
import '../../authentication/data/auth_providers.dart';
import '../domain/wallet.dart';

/// The signed-in customer's wallet: balance, history and saved cards.
///
/// Read-only for customers (Row Level Security): money only moves through
/// the payment gateway's server handler or the agency's administrators.
abstract interface class WalletRepository {
  Future<double> getBalance();
  Future<List<WalletTransaction>> getHistory(String customerId);
  Future<List<SavedCard>> getCards(String customerId);
  Future<void> setDefaultCard(String cardId);
  Future<void> removeCard(String cardId);
  Future<WalletSwitches> getSwitches();
}

class SupabaseWalletRepository implements WalletRepository {
  SupabaseWalletRepository(this._client);

  final SupabaseClient _client;

  static const historyLimit = 200;

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(AppFailure.from(error), stackTrace);
    }
  }

  @override
  Future<double> getBalance() => _guard(() async {
    final value = await _client.rpc<dynamic>('my_wallet_balance');
    return (value as num?)?.toDouble() ?? 0;
  });

  @override
  Future<List<WalletTransaction>> getHistory(String customerId) =>
      _guard(() async {
        // Filtered by owner: administrators who also use the app see only
        // their own wallet.
        final rows = await _client
            .from('wallet_transactions')
            .select(WalletTransaction.columns)
            .eq('customer_id', customerId)
            .order('created_at', ascending: false)
            .limit(historyLimit);
        return rows.map(WalletTransaction.fromJson).toList();
      });

  @override
  Future<List<SavedCard>> getCards(String customerId) => _guard(() async {
    final rows = await _client
        .from('saved_cards')
        .select(SavedCard.columns)
        .eq('customer_id', customerId)
        .order('created_at');
    return rows.map(SavedCard.fromJson).toList();
  });

  @override
  Future<void> setDefaultCard(String cardId) => _guard(
    () => _client.rpc<void>('set_default_card', params: {'p_card': cardId}),
  );

  @override
  Future<void> removeCard(String cardId) => _guard(() async {
    await _client
        .from('saved_cards')
        .delete()
        .eq('id', cardId)
        .select('id')
        .single();
  });

  @override
  Future<WalletSwitches> getSwitches() async {
    try {
      final rows = await _client
          .from('app_settings')
          .select('key, value')
          .inFilter('key', ['payments.cards_enabled', 'wallet.top_up_enabled']);
      bool on(String key) => rows.any((r) => r['key'] == key && r['value'] == true);
      return WalletSwitches(
        cardPaymentsEnabled: on('payments.cards_enabled'),
        topUpEnabled: on('wallet.top_up_enabled'),
      );
    } on Object {
      // Payments stay off when the switches cannot be read.
      return const WalletSwitches();
    }
  }
}

/// Used when the app has no Supabase settings.
class UnavailableWalletRepository implements WalletRepository {
  const UnavailableWalletRepository();

  static const _failure = ServerFailure(
    message: 'The wallet cannot be loaded: the app is not connected to its '
        'server.',
  );

  @override
  Future<double> getBalance() => Future.error(_failure);

  @override
  Future<List<WalletTransaction>> getHistory(String customerId) =>
      Future.error(_failure);

  @override
  Future<List<SavedCard>> getCards(String customerId) => Future.error(_failure);

  @override
  Future<void> setDefaultCard(String cardId) => Future.error(_failure);

  @override
  Future<void> removeCard(String cardId) => Future.error(_failure);

  @override
  Future<WalletSwitches> getSwitches() async => const WalletSwitches();
}

final walletRepositoryProvider = Provider<WalletRepository>((ref) {
  if (!Env.isSupabaseConfigured) return const UnavailableWalletRepository();
  return SupabaseWalletRepository(ref.watch(supabaseClientProvider));
});

/// Balance and history together, so they always agree on screen.
typedef WalletOverview = ({double balance, List<WalletTransaction> history});

final walletOverviewProvider = FutureProvider<WalletOverview?>((ref) async {
  final user = await ref.watch(authStateProvider.future);
  if (user == null) return null;
  final repository = ref.watch(walletRepositoryProvider);
  final results = await Future.wait<Object>([
    repository.getBalance(),
    repository.getHistory(user.id),
  ]);
  return (
    balance: results[0] as double,
    history: results[1] as List<WalletTransaction>,
  );
});

final savedCardsProvider = FutureProvider<List<SavedCard>>((ref) async {
  final user = await ref.watch(authStateProvider.future);
  if (user == null) return const <SavedCard>[];
  return ref.watch(walletRepositoryProvider).getCards(user.id);
});

final walletSwitchesProvider = FutureProvider<WalletSwitches>(
  (ref) => ref.watch(walletRepositoryProvider).getSwitches(),
);
