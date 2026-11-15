import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env.dart';
import '../errors/app_failure.dart';

/// Connects to Supabase. Called once from `main()` before the app starts.
///
/// If `env.json` has no Supabase settings the app still starts (useful for
/// UI work), but every feature that needs the backend will report it.
Future<void> initSupabase() async {
  if (!Env.isSupabaseConfigured) {
    debugPrint(
      'Supabase is not configured. Add SUPABASE_URL and '
      'SUPABASE_PUBLISHABLE_KEY to env.json and run with '
      '--dart-define-from-file=env.json',
    );
    return;
  }

  await Supabase.initialize(
    url: Env.supabaseUrl,
    publishableKey: Env.supabasePublishableKey,
  );
}

/// The shared Supabase client. Repositories read it through this provider so
/// tests can replace it.
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  if (!Env.isSupabaseConfigured) {
    throw const ServerFailure(
      message: 'The app is not connected to its server. Please contact support.',
    );
  }
  return Supabase.instance.client;
});

enum BackendStatus { notConfigured, connected }

/// Checks that the app can reach the database (calls `public.health_check`).
final backendStatusProvider = FutureProvider<BackendStatus>(
  (ref) async {
    if (!Env.isSupabaseConfigured) return BackendStatus.notConfigured;

    final client = ref.watch(supabaseClientProvider);
    try {
      final result = await client
          .rpc<Map<String, dynamic>>('health_check')
          .timeout(const Duration(seconds: 10));
      if (result['status'] != 'ok') throw const ServerFailure();
      return BackendStatus.connected;
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(AppFailure.from(error), stackTrace);
    }
  },
  isAutoDispose: true,
  // Show the error straight away; the user can tap "Try again".
  retry: (retryCount, error) => null,
);
