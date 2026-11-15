import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_maids/core/errors/app_failure.dart';
import 'package:golden_maids/features/authentication/domain/auth_repository.dart';
import 'package:golden_maids/features/home/data/service_location.dart';

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

  testWidgets('shows greeting, banners, categories and popular services', (
    tester,
  ) async {
    await pumpTestApp(tester, auth: auth, catalog: catalog);

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Hello, Sarah'), findsOneWidget);
    expect(find.text('Dubai, UAE'), findsOneWidget);
    expect(find.text('What services do you want to use?'), findsOneWidget);
    expect(find.text('Find Your Perfect Maid'), findsOneWidget);

    expect(find.text('General Cleaning'), findsOneWidget);
    expect(find.text('2-Year Maid Visa'), findsOneWidget);

    expect(find.text('Featured Maids'), findsOneWidget);
    expect(find.text('Wanjiru Kamau'), findsOneWidget);

    await scrollHomeTo(tester, find.text('AED 45 / hour'));
    expect(find.text('Home Cleaning'), findsOneWidget);
    expect(find.text('Price on request'), findsOneWidget);
    expect(find.text('AED 45 / hour'), findsOneWidget);
  });

  testWidgets('an offer banner shows its percentage and opens its target', (
    tester,
  ) async {
    await pumpTestApp(tester, auth: auth, catalog: catalog);

    // Swipe to the second banner.
    await tester.drag(find.text('Find Your Perfect Maid'), const Offset(-400, 0));
    await settle(tester);
    expect(find.text('20% OFF'), findsOneWidget);

    await tapAndSettle(tester, find.text('Book Now'));
    expect(find.text('Move-In Cleaning'), findsOneWidget); // category page
  });

  testWidgets('a category opens its list of services', (tester) async {
    await pumpTestApp(tester, auth: auth, catalog: catalog);

    await tapAndSettle(tester, find.text('General Cleaning'));
    expect(find.text('Regular home cleaning.'), findsOneWidget);
    expect(find.text('Home Cleaning'), findsOneWidget);
    expect(find.text('Move-In Cleaning'), findsOneWidget);
    expect(find.text('Hourly Maid'), findsNothing);
  });

  testWidgets('service details show price, duration and booking note', (
    tester,
  ) async {
    await pumpTestApp(tester, auth: auth, catalog: catalog);

    await scrollHomeTo(tester, find.text('AED 45 / hour'));
    await tapAndSettle(tester, find.text('AED 45 / hour'));
    expect(find.text('Hourly Maid'), findsWidgets);
    expect(find.text('AED 45 / hour'), findsOneWidget);
    expect(find.text('2 h'), findsOneWidget);
    expect(find.textContaining('Online booking'), findsOneWidget);
  });

  testWidgets('search finds services and can filter by category', (
    tester,
  ) async {
    await pumpTestApp(tester, auth: auth, catalog: catalog);

    await tapAndSettle(tester, find.byType(TextField).first);
    expect(find.text('Browse categories'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'clean');
    await settle(tester);
    expect(find.text('2 results'), findsOneWidget);
    expect(find.text('Home Cleaning'), findsOneWidget);
    expect(find.text('Move-In Cleaning'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'xyz');
    await settle(tester);
    expect(find.text('No results'), findsOneWidget);
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
    expect(find.text('General Cleaning'), findsNothing);

    catalog.failure = null;
    await tapAndSettle(tester, find.text('Try again').first);
    await tapAndSettle(tester, find.text('Try again').first);
    await tapAndSettle(tester, find.text('Try again').first);
    expect(find.text('General Cleaning'), findsOneWidget);
  });

  testWidgets('the bell opens notifications', (tester) async {
    await pumpTestApp(tester, auth: auth, catalog: catalog);

    await tapAndSettle(tester, find.byTooltip('Notifications'));
    expect(find.text('No notifications yet'), findsOneWidget);
  });
}
