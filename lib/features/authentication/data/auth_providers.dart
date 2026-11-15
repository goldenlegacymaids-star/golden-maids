import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/env.dart';
import '../../../core/services/supabase_providers.dart';
import '../domain/auth_repository.dart';
import 'supabase_auth_repository.dart';

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  if (!Env.isSupabaseConfigured) return const UnavailableAuthRepository();
  return SupabaseAuthRepository(ref.watch(supabaseClientProvider).auth);
});

/// The signed-in user, updated whenever the session changes.
final authStateProvider = StreamProvider<AppUser?>(
  (ref) => ref.watch(authRepositoryProvider).authStateChanges(),
);

/// Whether "Send by SMS instead" is offered (remote switch in
/// `public.app_settings`). Defaults to off if it cannot be loaded.
final smsFallbackEnabledProvider = FutureProvider<bool>(
  (ref) async {
    if (!Env.isSupabaseConfigured) return false;
    try {
      final row = await ref
          .watch(supabaseClientProvider)
          .from('app_settings')
          .select('value')
          .eq('key', 'auth.sms_fallback_enabled')
          .maybeSingle();
      return row?['value'] == true;
    } on Object {
      return false;
    }
  },
  retry: (retryCount, error) => null,
);
