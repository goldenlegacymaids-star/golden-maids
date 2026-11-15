import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Small on-device settings (e.g. "onboarding seen").
///
/// Loaded once in `main()` and injected with `overrideWithValue`, so it can be
/// read synchronously everywhere. Never store personal or secret data here.
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError(
    'sharedPreferencesProvider must be overridden in main().',
  ),
);
