import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/supabase_providers.dart';
import '../../authentication/data/auth_providers.dart';
import '../domain/account_deletion.dart';

/// Account deletion requests. Administrators process each request: they
/// delete the sign-in and personal details and keep anonymised records.
abstract interface class AccountDeletionRepository {
  /// The signed-in customer's pending request, if any.
  Future<AccountDeletionRequest?> getPendingRequest();

  Future<void> requestDeletion({String reason = ''});

  /// Withdraws a pending request (before the agency processes it).
  Future<void> withdraw(String requestId);
}

class SupabaseAccountDeletionRepository implements AccountDeletionRepository {
  SupabaseAccountDeletionRepository(this._client);

  final SupabaseClient _client;

  static const String _table = 'account_deletion_requests';

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on PostgrestException catch (error, stackTrace) {
      if (error.code == '23505') {
        Error.throwWithStackTrace(
          ValidationFailure(
            message: 'You have already asked us to delete your account.',
            cause: error,
          ),
          stackTrace,
        );
      }
      Error.throwWithStackTrace(AppFailure.from(error), stackTrace);
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(AppFailure.from(error), stackTrace);
    }
  }

  String _userId() {
    final id = _client.auth.currentUser?.id;
    if (id == null) throw const AuthFailure();
    return id;
  }

  @override
  Future<AccountDeletionRequest?> getPendingRequest() => _guard(() async {
    final row = await _client
        .from(_table)
        .select(AccountDeletionRequest.columns)
        .eq('user_id', _userId())
        .eq('status', 'pending')
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    return row == null ? null : AccountDeletionRequest.fromJson(row);
  });

  @override
  Future<void> requestDeletion({String reason = ''}) => _guard(() async {
    _userId();
    await _client.from(_table).insert({'reason': reason.trim()});
  });

  @override
  Future<void> withdraw(String requestId) => _guard(() async {
    // A refused change returns no rows rather than an error.
    final rows = await _client
        .from(_table)
        .update({'status': 'withdrawn'})
        .eq('id', requestId)
        .eq('user_id', _userId())
        .eq('status', 'pending')
        .select('id');
    if (rows.isEmpty) throw const NotFoundFailure();
  });
}

/// Used when the app has no Supabase settings.
class UnavailableAccountDeletionRepository
    implements AccountDeletionRepository {
  const UnavailableAccountDeletionRepository();

  static const _failure = ServerFailure(
    message: 'Account requests are unavailable: the app is not connected to '
        'its server.',
  );

  @override
  Future<AccountDeletionRequest?> getPendingRequest() => Future.error(_failure);

  @override
  Future<void> requestDeletion({String reason = ''}) => Future.error(_failure);

  @override
  Future<void> withdraw(String requestId) => Future.error(_failure);
}

final accountDeletionRepositoryProvider = Provider<AccountDeletionRepository>((
  ref,
) {
  if (!Env.isSupabaseConfigured) {
    return const UnavailableAccountDeletionRepository();
  }
  return SupabaseAccountDeletionRepository(ref.watch(supabaseClientProvider));
});

/// The signed-in customer's pending deletion request (null for guests).
final pendingDeletionProvider = FutureProvider<AccountDeletionRequest?>(
  (ref) async {
    final user = await ref.watch(authStateProvider.future);
    if (user == null) return null;
    return ref.watch(accountDeletionRepositoryProvider).getPendingRequest();
  },
  isAutoDispose: true,
);
