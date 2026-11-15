import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/supabase_providers.dart';
import '../../authentication/data/auth_providers.dart';
import '../domain/profile.dart';

/// Reads and updates the signed-in user's profile (`public.profiles`).
abstract interface class ProfileRepository {
  Future<Profile> getMyProfile();
}

class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<Profile> getMyProfile() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const AuthFailure();
    try {
      final row = await _client
          .from('profiles')
          .select('id, full_name, email, phone, avatar_url')
          .eq('id', userId)
          .single();
      return Profile.fromJson(row);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(AppFailure.from(error), stackTrace);
    }
  }
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  return SupabaseProfileRepository(ref.watch(supabaseClientProvider));
});

/// The signed-in user's profile; reloads when the user changes.
final myProfileProvider = FutureProvider<Profile?>(
  (ref) async {
    final user = await ref.watch(authStateProvider.future);
    if (user == null || !Env.isSupabaseConfigured) return null;
    return ref.watch(profileRepositoryProvider).getMyProfile();
  },
  retry: (retryCount, error) => null,
);
