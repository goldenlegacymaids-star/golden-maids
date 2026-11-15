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

  /// Row Level Security only allows changing your own name and photo.
  Future<void> updateFullName(String fullName);
}

class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this._client);

  final SupabaseClient _client;

  static const _columns = 'id, full_name, email, phone, avatar_url';

  String _userId() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw const AuthFailure();
    return userId;
  }

  @override
  Future<Profile> getMyProfile() async {
    final userId = _userId();
    try {
      final row = await _client
          .from('profiles')
          .select(_columns)
          .eq('id', userId)
          .single();
      return Profile.fromJson(row);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(AppFailure.from(error), stackTrace);
    }
  }

  @override
  Future<void> updateFullName(String fullName) async {
    final userId = _userId();
    try {
      await _client
          .from('profiles')
          .update({'full_name': fullName})
          .eq('id', userId);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(AppFailure.from(error), stackTrace);
    }
  }
}

/// Used when the app has no Supabase settings.
class UnavailableProfileRepository implements ProfileRepository {
  const UnavailableProfileRepository();

  static const _failure = ServerFailure(
    message: 'Your profile is not available: the app is not connected to '
        'its server.',
  );

  @override
  Future<Profile> getMyProfile() => Future.error(_failure);

  @override
  Future<void> updateFullName(String fullName) => Future.error(_failure);
}

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  if (!Env.isSupabaseConfigured) return const UnavailableProfileRepository();
  return SupabaseProfileRepository(ref.watch(supabaseClientProvider));
});

/// The signed-in user's profile (`null` for guests); reloads when the user
/// changes. Invalidate it after editing the profile.
final myProfileProvider = FutureProvider<Profile?>(
  (ref) async {
    final user = await ref.watch(authStateProvider.future);
    if (user == null) return null;
    return ref.watch(profileRepositoryProvider).getMyProfile();
  },
  retry: (retryCount, error) => null,
);
