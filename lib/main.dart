import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/config/font_licences.dart';
import 'core/services/shared_preferences_provider.dart';
import 'core/services/supabase_providers.dart';

/// Application entry point.
///
/// Keep this file minimal: start-up work (Supabase, Firebase, error
/// reporting) is added here step by step, and all UI lives in [GoldenMaidsApp].
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicences();

  final preferences = await SharedPreferences.getInstance();
  await initSupabase();

  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(preferences)],
      child: const GoldenMaidsApp(),
    ),
  );
}
