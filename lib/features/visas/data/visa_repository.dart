import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/supabase_providers.dart';
import '../../authentication/data/auth_providers.dart';
import '../domain/visa_application.dart';

/// The signed-in customer's visa applications (My Visa Applications).
///
/// The agency moves the steps and adds the visa documents on the staff
/// website; customers only read. Files are in the private `visa-documents`
/// bucket, which only the customer and recruitment staff can open.
abstract interface class VisaRepository {
  Future<List<VisaApplication>> getMine(String customerId);

  /// A link to the file that works for a few minutes.
  Future<String> viewUrl(VisaDocument document);
}

class SupabaseVisaRepository implements VisaRepository {
  SupabaseVisaRepository(this._client);

  final SupabaseClient _client;

  static const bucket = 'visa-documents';

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(AppFailure.from(error), stackTrace);
    }
  }

  @override
  Future<List<VisaApplication>> getMine(String customerId) => _guard(() async {
    // Filtered by owner: staff who also use the app see only their own.
    final rows = await _client
        .from('visa_applications')
        .select(VisaApplication.columns)
        .eq('hiring_requests.customer_id', customerId)
        .order('created_at', ascending: false);
    return rows.map(VisaApplication.fromJson).toList();
  });

  @override
  Future<String> viewUrl(VisaDocument document) => _guard(
    () => _client.storage.from(bucket).createSignedUrl(document.storagePath, 300),
  );
}

/// Used when the app has no Supabase settings.
class UnavailableVisaRepository implements VisaRepository {
  const UnavailableVisaRepository();

  static const _failure = ServerFailure(
    message:
        'Visa applications cannot be loaded: the app is not connected to its '
        'server.',
  );

  @override
  Future<List<VisaApplication>> getMine(String customerId) =>
      Future.error(_failure);

  @override
  Future<String> viewUrl(VisaDocument document) => Future.error(_failure);
}

final visaRepositoryProvider = Provider<VisaRepository>((ref) {
  if (!Env.isSupabaseConfigured) return const UnavailableVisaRepository();
  return SupabaseVisaRepository(ref.watch(supabaseClientProvider));
});

/// The signed-in customer's visa applications (empty for guests).
final myVisaApplicationsProvider = FutureProvider<List<VisaApplication>>((
  ref,
) async {
  final user = await ref.watch(authStateProvider.future);
  if (user == null) return const <VisaApplication>[];
  return ref.watch(visaRepositoryProvider).getMine(user.id);
});
