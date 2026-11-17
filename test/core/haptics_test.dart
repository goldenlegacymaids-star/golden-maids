import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_maids/core/errors/app_failure.dart';
import 'package:golden_maids/core/haptics/haptics.dart';
import 'package:golden_maids/features/authentication/domain/auth_repository.dart';

import '../helpers/fake_auth_repository.dart';
import '../helpers/fake_candidate_repository.dart';
import '../helpers/test_app.dart';

const _profileTab = Icons.person_outline_rounded;

void main() {
  late FakeAuthRepository auth;
  late FakeCandidateRepository candidates;
  late List<HapticKind> haptics;

  setUp(() {
    auth = FakeAuthRepository(
      signedInUser: const AppUser(id: 'u1', fullName: 'Sarah Khan'),
    );
    candidates = FakeCandidateRepository();
    haptics = [];
  });
  tearDown(() => auth.dispose());

  testWidgets('switching tabs ticks; the Profile switch turns it off', (
    tester,
  ) async {
    await pumpTestApp(tester, auth: auth, haptics: haptics);

    await openTab(tester, _profileTab);
    expect(haptics, [HapticKind.selection]);

    await scrollTo(tester, find.text('Vibration'));
    expect(find.text('Vibration'), findsOneWidget);
    await tapAndSettle(tester, find.text('Vibration'));
    haptics.clear();

    // Off: nothing vibrates any more, and the choice is remembered.
    await openTab(tester, Icons.home_outlined);
    expect(haptics, isEmpty);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    expect(container.read(hapticsEnabledProvider), isFalse);
  });

  testWidgets('saving a maid taps lightly; a failure buzzes', (tester) async {
    await pumpTestApp(
      tester,
      auth: auth,
      candidates: candidates,
      haptics: haptics,
    );

    await tapAndSettle(tester, find.byTooltip('Save').first);
    expect(haptics, [HapticKind.light]);

    haptics.clear();
    candidates.failure = const NetworkFailure();
    await tapAndSettle(tester, find.byTooltip('Remove from saved').first);
    expect(haptics, [HapticKind.light, HapticKind.error]);
  });
}
