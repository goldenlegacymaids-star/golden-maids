import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_maids/core/errors/app_failure.dart';
import 'package:golden_maids/core/widgets/app_logo.dart';
import 'package:golden_maids/core/widgets/app_search_bar.dart';
import 'package:golden_maids/features/authentication/domain/auth_repository.dart';
import 'package:golden_maids/features/home/data/service_location.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_catalog_repository.dart';
import '../../helpers/test_app.dart';

void main() {
  late FakeAuthRepository auth;
  late FakeCatalogRepository catalog;

  setUp(() {
    auth = FakeAuthRepository(
      signedInUser: const AppUser(id: 'u1', fullName: 'Sarah Khan'),
    );
    catalog = FakeCatalogRepository();
  });
  tearDown(() => auth.dispose());

  testWidgets('shows greeting, logo, banners, hiring a maid and featured maids', (
    tester,
  ) async {
    await pumpTestApp(tester, auth: auth, catalog: catalog);

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Hello, Sarah'), findsOneWidget);
    expect(find.byType(AppLogo), findsOneWidget);
    expect(find.text('Dubai, UAE'), findsOneWidget);
    expect(find.text('Find Your Perfect Maid'), findsOneWidget);

    // Offers first, then search and hiring a maid.
    final offers = tester.getTopLeft(find.text('Find Your Perfect Maid')).dy;
    final search = tester.getTopLeft(find.byType(AppSearchBar)).dy;
    final hire = tester.getTopLeft(find.text('Hire a Maid')).dy;
    expect(offers, lessThan(search));
    expect(search, lessThan(hire));

    await scrollHomeTo(tester, find.text('Wanjiru Kamau'));
    expect(find.text('Featured Maids'), findsOneWidget);
    expect(find.text('Wanjiru Kamau'), findsOneWidget);

    // Home services are no longer offered.
    expect(find.text('What services do you want to use?'), findsNothing);
    expect(find.text('Popular Services'), findsNothing);
    expect(find.text('General Cleaning'), findsNothing);
  });

  testWidgets('an offer banner shows its percentage and opens the hire page', (
    tester,
  ) async {
    await pumpTestApp(tester, auth: auth, catalog: catalog);

    // Swipe to the second banner.
    await tester.drag(find.text('Find Your Perfect Maid'), const Offset(-400, 0));
    await settle(tester);
    expect(find.text('20% OFF'), findsOneWidget);

    await tapAndSettle(tester, find.text('Hire now'));
    expect(find.text('Find a Maid'), findsOneWidget);
  });

  testWidgets('search starts with a hint and a link to all maids', (
    tester,
  ) async {
    await pumpTestApp(tester, auth: auth, catalog: catalog);

    await tapAndSettle(tester, find.byType(TextField).first);
    expect(find.text('See all maids'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'xyz');
    await settle(tester);
    expect(find.text('No results'), findsOneWidget);
  });

  testWidgets('search finds maids by nationality, name or code', (
    tester,
  ) async {
    await pumpTestApp(tester, auth: auth, catalog: catalog);

    await tapAndSettle(tester, find.byType(TextField).first);
    await tester.enterText(find.byType(TextField), 'ken');
    await settle(tester);
    expect(find.text('Maids · 1'), findsOneWidget);
    expect(find.text('Wanjiru Kamau'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'gm-00004');
    await settle(tester);
    expect(find.text('Maids · 1'), findsOneWidget);
    expect(find.text('GM-00004'), findsOneWidget);
    expect(find.text('Wanjiru Kamau'), findsNothing);

    await tapAndSettle(tester, find.text('GM-00004'));
    expect(find.text('Search'), findsNothing); // the maid's profile opened
  });

  testWidgets('Hire a Maid cards open the maid list on their visa and place', (
    tester,
  ) async {
    await pumpTestApp(tester, auth: auth, catalog: catalog);

    expect(find.text('GCC Sponsor Visa'), findsOneWidget);
    expect(find.text('Company Visa'), findsOneWidget);
    await tapAndSettle(
      tester,
      find.bySemanticsLabel('GCC Sponsor Visa, Outside the UAE'),
    );
    expect(find.text('Find a Maid'), findsOneWidget);
  });

  testWidgets('choosing a service location is remembered', (tester) async {
    await pumpTestApp(tester, auth: auth, catalog: catalog);

    await tapAndSettle(tester, find.text('Dubai, UAE'));
    await tapAndSettle(tester, find.text('Sharjah'));
    expect(find.text('Sharjah, UAE'), findsOneWidget);
  });

  testWidgets('a saved service location is restored', (tester) async {
    await pumpTestApp(
      tester,
      auth: auth,
      catalog: catalog,
      preferences: {ServiceLocationNotifier.storageKey: 'Ajman'},
    );
    expect(find.text('Ajman, UAE'), findsOneWidget);
  });

  testWidgets('loading errors show a retry that recovers', (tester) async {
    catalog.failure = const NetworkFailure();
    await pumpTestApp(tester, auth: auth, catalog: catalog);

    expect(find.text('Try again'), findsWidgets);
    expect(find.text('Find Your Perfect Maid'), findsNothing);

    catalog.failure = null;
    await tapAndSettle(tester, find.text('Try again').first);
    expect(find.text('Find Your Perfect Maid'), findsOneWidget);
  });

  testWidgets('banners saved on the phone show at once, even offline', (
    tester,
  ) async {
    // First launch: the server's banners are saved.
    await pumpTestApp(tester, auth: auth, catalog: catalog);
    expect(find.text('Find Your Perfect Maid'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('cache.home_promotions.v1');
    expect(saved, contains('Find Your Perfect Maid'));

    // Next launch without a connection: the saved banners are shown.
    catalog.failure = const NetworkFailure();
    await pumpTestApp(
      tester,
      auth: auth,
      catalog: catalog,
      preferences: {'cache.home_promotions.v1': saved!},
    );
    expect(find.text('Find Your Perfect Maid'), findsOneWidget);
  });

  testWidgets('the bell opens notifications', (tester) async {
    await pumpTestApp(tester, auth: auth, catalog: catalog);

    await tapAndSettle(tester, find.byTooltip('Notifications'));
    expect(find.text('No notifications yet'), findsOneWidget);
  });
}
