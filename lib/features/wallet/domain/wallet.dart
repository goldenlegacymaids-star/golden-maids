import 'package:intl/intl.dart';

/// What a wallet entry is (`wallet_transactions.kind`).
enum WalletKind {
  topUp('top_up', 'Top-up'),
  payment('payment', 'Payment'),
  refund('refund', 'Refund'),
  credit('credit', 'Credit from Golden Maids'),
  adjustment('adjustment', 'Balance correction');

  const WalletKind(this.value, this.label);

  final String value;
  final String label;

  static WalletKind fromValue(String? value) {
    for (final kind in values) {
      if (kind.value == value) return kind;
    }
    return WalletKind.adjustment;
  }
}

/// `pending`, `completed`, `failed`, `cancelled`.
enum WalletStatus {
  pending('pending', 'Pending'),
  completed('completed', 'Completed'),
  failed('failed', 'Failed'),
  cancelled('cancelled', 'Cancelled');

  const WalletStatus(this.value, this.label);

  final String value;
  final String label;

  static WalletStatus fromValue(String? value) {
    for (final status in values) {
      if (status.value == value) return status;
    }
    return WalletStatus.completed;
  }
}

/// One entry of the wallet history (`public.wallet_transactions`). Written
/// only by the payment gateway's server handler or by administrators.
class WalletTransaction {
  const WalletTransaction({
    required this.id,
    required this.reference,
    required this.kind,
    required this.method,
    required this.amount,
    required this.balanceEffect,
    required this.status,
    required this.createdAt,
    this.description = '',
    this.cardBrand,
    this.cardLast4,
  });

  factory WalletTransaction.fromJson(Map<String, dynamic> json) =>
      WalletTransaction(
        id: json['id'] as String,
        reference: json['reference'] as String,
        kind: WalletKind.fromValue(json['kind'] as String?),
        method: json['method'] as String,
        amount: (json['amount'] as num).toDouble(),
        balanceEffect: (json['balance_effect'] as num).toDouble(),
        status: WalletStatus.fromValue(json['status'] as String?),
        description: (json['description'] as String?) ?? '',
        cardBrand: json['card_brand'] as String?,
        cardLast4: json['card_last4'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  static const String columns =
      'id, reference, kind, method, amount, balance_effect, status, '
      'description, card_brand, card_last4, created_at';

  final String id;
  final String reference;
  final WalletKind kind;

  /// `card`, `wallet`, `cash` or `agency`.
  final String method;
  final double amount;

  /// Change to the wallet balance: + in, − out, 0 for card/cash payments.
  final double balanceEffect;
  final WalletStatus status;
  final String description;
  final String? cardBrand;
  final String? cardLast4;
  final DateTime createdAt;

  /// Money coming in (shown in green with +).
  bool get isIncoming =>
      balanceEffect > 0 || (kind == WalletKind.refund && balanceEffect == 0);

  /// "Visa •••• 4242", "Wallet", "Cash", "Golden Maids".
  String get methodLabel => switch (method) {
    'card' =>
      cardLast4 == null
          ? 'Card'
          : '${cardBrandLabel(cardBrand)} •••• $cardLast4',
    'wallet' => 'Wallet balance',
    'cash' => 'Cash',
    _ => 'Golden Maids',
  };
}

/// A card saved through the payment gateway (brand, last 4, expiry only).
class SavedCard {
  const SavedCard({
    required this.id,
    required this.brand,
    required this.last4,
    required this.expMonth,
    required this.expYear,
    this.isDefault = false,
  });

  factory SavedCard.fromJson(Map<String, dynamic> json) => SavedCard(
    id: json['id'] as String,
    brand: json['brand'] as String,
    last4: json['last4'] as String,
    expMonth: (json['exp_month'] as num).toInt(),
    expYear: (json['exp_year'] as num).toInt(),
    isDefault: json['is_default'] as bool? ?? false,
  );

  static const String columns =
      'id, brand, last4, exp_month, exp_year, is_default';

  final String id;
  final String brand;
  final String last4;
  final int expMonth;
  final int expYear;
  final bool isDefault;

  /// "Expires 12/30".
  String get expiryLabel =>
      'Expires ${expMonth.toString().padLeft(2, '0')}/'
      '${(expYear % 100).toString().padLeft(2, '0')}';

  bool isExpired(DateTime now) =>
      expYear < now.year || (expYear == now.year && expMonth < now.month);
}

String cardBrandLabel(String? brand) => switch (brand) {
  'visa' => 'Visa',
  'mastercard' => 'Mastercard',
  'amex' => 'American Express',
  _ => 'Card',
};

/// Remote switches (`public.app_settings`), both off until the payment
/// gateway is connected / top-ups are confirmed as allowed.
class WalletSwitches {
  const WalletSwitches({
    this.cardPaymentsEnabled = false,
    this.topUpEnabled = false,
  });

  final bool cardPaymentsEnabled;
  final bool topUpEnabled;
}

final _monthYear = DateFormat('MMMM yyyy');
final _dayTime = DateFormat('d MMM, h:mm a');

/// "November 2026": heading for a month of history.
String walletMonth(DateTime at) => _monthYear.format(at.toLocal());

/// "16 Nov, 3:05 PM".
String walletTime(DateTime at) => _dayTime.format(at.toLocal());
