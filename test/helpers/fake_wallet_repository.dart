import 'package:golden_maids/core/errors/app_failure.dart';
import 'package:golden_maids/features/wallet/data/wallet_repository.dart';
import 'package:golden_maids/features/wallet/domain/wallet.dart';

/// In-memory [WalletRepository].
class FakeWalletRepository implements WalletRepository {
  FakeWalletRepository({
    this.balance = 0,
    List<WalletTransaction>? history,
    List<SavedCard>? cards,
    this.switches = const WalletSwitches(),
  }) : history = [...?history],
       cards = [...?cards];

  double balance;
  final List<WalletTransaction> history;
  final List<SavedCard> cards;
  WalletSwitches switches;
  AppFailure? failure;

  void _check() {
    final error = failure;
    if (error != null) throw error;
  }

  @override
  Future<double> getBalance() async {
    _check();
    return balance;
  }

  @override
  Future<List<WalletTransaction>> getHistory(String customerId) async {
    _check();
    return List.of(history);
  }

  @override
  Future<List<SavedCard>> getCards(String customerId) async {
    _check();
    return List.of(cards);
  }

  @override
  Future<void> setDefaultCard(String cardId) async {
    _check();
    for (var i = 0; i < cards.length; i++) {
      final c = cards[i];
      cards[i] = SavedCard(
        id: c.id,
        brand: c.brand,
        last4: c.last4,
        expMonth: c.expMonth,
        expYear: c.expYear,
        isDefault: c.id == cardId,
      );
    }
  }

  @override
  Future<void> removeCard(String cardId) async {
    _check();
    cards.removeWhere((c) => c.id == cardId);
  }

  @override
  Future<WalletSwitches> getSwitches() async => switches;

  static WalletTransaction entry({
    required String id,
    required WalletKind kind,
    required double amount,
    double? effect,
    String method = 'agency',
    String description = '',
    WalletStatus status = WalletStatus.completed,
    DateTime? at,
    String? cardBrand,
    String? cardLast4,
  }) => WalletTransaction(
    id: id,
    reference: 'WT-2026-00000$id',
    kind: kind,
    method: method,
    amount: amount,
    balanceEffect: effect ?? amount,
    status: status,
    description: description,
    cardBrand: cardBrand,
    cardLast4: cardLast4,
    createdAt: at ?? DateTime(2026, 11, 16, 15, 5),
  );
}
