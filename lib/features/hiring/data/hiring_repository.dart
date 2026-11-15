import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/supabase_providers.dart';
import '../../authentication/data/auth_providers.dart';
import '../domain/hiring_request.dart';

/// The signed-in customer's hiring requests.
///
/// Row Level Security lets customers read only their own requests and
/// only cancel them before shortlisting; the database also checks the
/// package, duration, sponsor nationality and worker availability.
abstract interface class HiringRepository {
  /// Submits a request and returns its reference (HR-…).
  Future<String> submit(HiringDraft draft);

  /// The customer's requests, newest first.
  Future<List<HiringRequest>> getMyRequests();

  Future<HiringRequest> getRequest(String id);

  /// Status changes visible to the customer, oldest first.
  Future<List<HiringStatusEvent>> getHistory(String requestId);

  Future<void> cancel(String requestId);
}

class SupabaseHiringRepository implements HiringRepository {
  SupabaseHiringRepository(this._client);

  final SupabaseClient _client;

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(AppFailure.from(error), stackTrace);
    }
  }

  String _userId() {
    final id = _client.auth.currentUser?.id;
    if (id == null) {
      throw const AuthFailure();
    }
    return id;
  }

  @override
  Future<String> submit(HiringDraft draft) => _guard(() async {
    final row = await _client
        .from('hiring_requests')
        .insert(draft.toInsertJson())
        .select('reference')
        .single();
    return row['reference'] as String;
  });

  @override
  Future<List<HiringRequest>> getMyRequests() => _guard(() async {
    // Staff accounts can read every request, so the customer's own are
    // selected explicitly.
    final rows = await _client
        .from('hiring_requests')
        .select(HiringRequest.columns)
        .eq('customer_id', _userId())
        .order('created_at', ascending: false);
    return rows.map(HiringRequest.fromJson).toList();
  });

  @override
  Future<HiringRequest> getRequest(String id) => _guard(() async {
    final row = await _client
        .from('hiring_requests')
        .select(HiringRequest.columns)
        .eq('id', id)
        .eq('customer_id', _userId())
        .single();
    return HiringRequest.fromJson(row);
  });

  @override
  Future<List<HiringStatusEvent>> getHistory(String requestId) =>
      _guard(() async {
        final rows = await _client
            .from('hiring_request_history')
            .select('status, note, created_at')
            .eq('request_id', requestId)
            .eq('is_customer_visible', true)
            .order('created_at', ascending: true);
        return rows.map(HiringStatusEvent.fromJson).toList();
      });

  @override
  Future<void> cancel(String requestId) => _guard(() async {
    final rows = await _client
        .from('hiring_requests')
        .update({'status': HiringStatus.cancelled.value})
        .eq('id', requestId)
        .select('id');
    if (rows.isEmpty) throw const NotFoundFailure();
  });
}

/// Used when the app has no Supabase settings.
class UnavailableHiringRepository implements HiringRepository {
  const UnavailableHiringRepository();

  static const _failure = ServerFailure(
    message: 'Hiring requests are unavailable: the app is not connected to '
        'its server.',
  );

  @override
  Future<String> submit(HiringDraft draft) => Future.error(_failure);

  @override
  Future<List<HiringRequest>> getMyRequests() => Future.error(_failure);

  @override
  Future<HiringRequest> getRequest(String id) => Future.error(_failure);

  @override
  Future<List<HiringStatusEvent>> getHistory(String requestId) =>
      Future.error(_failure);

  @override
  Future<void> cancel(String requestId) => Future.error(_failure);
}

final hiringRepositoryProvider = Provider<HiringRepository>((ref) {
  if (!Env.isSupabaseConfigured) return const UnavailableHiringRepository();
  return SupabaseHiringRepository(ref.watch(supabaseClientProvider));
});

/// The signed-in customer's requests (empty for guests).
final myHiringRequestsProvider = FutureProvider<List<HiringRequest>>(
  (ref) async {
    final user = await ref.watch(authStateProvider.future);
    if (user == null) return const <HiringRequest>[];
    return ref.watch(hiringRepositoryProvider).getMyRequests();
  },
  isAutoDispose: true,
);

final hiringRequestProvider = FutureProvider.family<HiringRequest, String>(
  (ref, id) => ref.watch(hiringRepositoryProvider).getRequest(id),
  isAutoDispose: true,
);

final hiringHistoryProvider =
    FutureProvider.family<List<HiringStatusEvent>, String>(
      (ref, id) => ref.watch(hiringRepositoryProvider).getHistory(id),
      isAutoDispose: true,
    );
