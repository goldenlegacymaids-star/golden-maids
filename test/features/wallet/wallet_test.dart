import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_maids/features/authentication/domain/auth_repository.dart';
import 'package:golden_maids/features/wallet/domain/wallet.dart';
import 'package:golden_maids/features/wallet/presentation/wallet_screen.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_wallet_repository.dart';
import '../../helpers/test_app.dart';

const _walletIcon = Icons.account_balance_wallet_outlined;
const _profileIcon = Icons.person_outline_rounded;

void main() {
  late FakeAuthRepository auth;
  late FakeWalletRepository wallet;

  setUp(() {
    auth = FakeAuthRepository(
      signedInUser: const AppUser(id: 'u1', fullName: 'Sarah Khan'),
    );
    wallet = FakeWalletRepository(
      balance: 30,
      history: [
        FakeWalletRepository.entry(
          id: '3',
          kind: WalletKind.payment,
          amount: 120,
          effect: 0,
          method: 'card',
          cardBrand: 'visa',
          cardLast4: '4242',
          description: 'Home Cleaning',
        ),
        FakeWalletRepository.entry(
          id: '2',
          kind: WalletKind.adjustment,
          amount: 20,
          effect: -20,
          description: 'Correction',
        ),
        FakeWalletRepository.entry(
          id: '1',
          kind: WalletKind.credit,
          amount: 50,
          description: 'Sorry for the delay',
          at: DateTime(2026, 10, 2, 9),
        ),
      ],
      cards: const [
        SavedCard(
          id: 'c1',
          brand: 'visa',
          last4: '4242',
          expMonth: 12,
          expYear: 2030,
          isDefault: true,
        ),
        SavedCard(
          id: 'c2',
          brand: 'mastercard',
          last4: '5555',
          expMonth: 1,
          expYear: 2031,
        ),
      ],
    );
  });
  tearDown(() => auth.dispose());

  Future<void> openWallet(WidgetTester tester) async {
    await pumpTestApp(tester, auth: auth, wallet: wallet);
    await openTab(tester, _walletIcon);
  }

  testWidgets('shows the balance and the history by month', (tester) async {
    await openWallet(tester);

    expect(find.text('AED 30.00'), findsOneWidget);
    expect(find.text('November 2026'), findsOneWidget);
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.text('Home Cleaning'), findsOneWidget);
    expect(find.text('Payment · Visa •••• 4242'), findsOneWidget);
    expect(find.text('AED 120.00'), findsOneWidget);
    expect(find.text('−AED 20.00'), findsOneWidget);
    expect(find.text('+AED 50.00'), findsOneWidget);
  });

  testWidgets('Add money explains that top-ups are coming', (tester) async {
    await openWallet(tester);

    await tapAndSettle(tester, find.text('Add money'));
    expect(find.text('Top-ups are coming soon'), findsOneWidget);
    expect(find.textContaining('never sees or stores'), findsOneWidget);
    await tapAndSettle(tester, find.text('OK'));
  });

  testWidgets('an empty wallet says so', (tester) async {
    wallet = FakeWalletRepository();
    await openWallet(tester);

    expect(find.text('AED 0.00'), findsOneWidget);
    expect(find.textContaining('No activity yet'), findsOneWidget);
  });

  testWidgets('saved cards: default, remove, and add is coming', (
    tester,
  ) async {
    await openWallet(tester);
    await tapAndSettle(tester, find.text('My cards'));

    expect(find.text('Payment Methods'), findsOneWidget);
    expect(find.text('Visa •••• 4242'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
    expect(find.text('Expires 12/30'), findsOneWidget);

    await tapAndSettle(tester, find.byTooltip('Card options').last);
    await tapAndSettle(tester, find.text('Make default'));
    expect(wallet.cards.last.isDefault, isTrue);
    expect(find.text('Default card updated.'), findsOneWidget);

    await tapAndSettle(tester, find.byTooltip('Card options').first);
    await tapAndSettle(tester, find.text('Remove'));
    await tapAndSettle(tester, find.widgetWithText(TextButton, 'Remove'));
    expect(wallet.cards.map((c) => c.last4), ['5555']);

    await tapAndSettle(tester, find.text('Add a card'));
    expect(find.text('Card payments are coming soon'), findsOneWidget);
  });

  testWidgets('Profile → Payment Methods opens the cards', (tester) async {
    await pumpTestApp(tester, auth: auth, wallet: wallet);
    await openTab(tester, _profileIcon);
    await tapAndSettle(tester, find.text('Payment Methods'));
    expect(find.text('Visa •••• 4242'), findsOneWidget);
  });

  test('amounts and card labels', () {
    expect(walletAmount(1250), 'AED 1,250.00');
    expect(walletAmount(45.5), 'AED 45.50');
    expect(cardBrandLabel('mastercard'), 'Mastercard');
    const card = SavedCard(
      id: 'x',
      brand: 'visa',
      last4: '1111',
      expMonth: 3,
      expYear: 2026,
    );
    expect(card.expiryLabel, 'Expires 03/26');
    expect(card.isExpired(DateTime(2026, 4)), isTrue);
    expect(card.isExpired(DateTime(2026, 3, 31)), isFalse);
  });
}
