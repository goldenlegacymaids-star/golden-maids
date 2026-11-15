import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/shared_preferences_provider.dart';

/// Remembers whether the user has completed onboarding on this device.
class OnboardingRepository {
  OnboardingRepository(this._prefs);

  /// Bump the version to show onboarding again after a major redesign.
  static const String seenKey = 'onboarding_seen_v1';

  final SharedPreferences _prefs;

  bool get hasSeenOnboarding => _prefs.getBool(seenKey) ?? false;

  Future<void> markSeen() async {
    await _prefs.setBool(seenKey, true);
  }
}

final onboardingRepositoryProvider = Provider<OnboardingRepository>(
  (ref) => OnboardingRepository(ref.watch(sharedPreferencesProvider)),
);
