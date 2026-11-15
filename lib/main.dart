import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'core/config/font_licences.dart';

/// Application entry point.
///
/// Keep this file minimal: start-up work (Supabase, Firebase, error
/// reporting) is added here step by step, and all UI lives in [GoldenMaidsApp].
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicences();

  runApp(const ProviderScope(child: GoldenMaidsApp()));
}
