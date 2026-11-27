import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/supabase_providers.dart';
import '../../authentication/data/auth_providers.dart';
import '../domain/billing_document.dart';

/// Receipts and invoices the agency added for the signed-in customer.
/// Read-only in the app; administrators add them on the staff website.
abstract interface class BillingRepository {
  /// Newest first.
  Future<List<BillingDocument>> getMine(String customerId);

  /// A link to the file that works for a few minutes.
  Future<String> fileUrl(BillingDocument document);
}

class SupabaseBillingRepository implements BillingRepository {
  SupabaseBillingRepository(this._client);

  final SupabaseClient _client;

  static const bucket = 'billing-documents';

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(AppFailure.from(error), stackTrace);
    }
  }

  @override
  Future<List<BillingDocument>> getMine(String customerId) => _guard(() async {
    // Filtered by owner: administrators who also use the app see only
    // their own.
    final rows = await _client
        .from('customer_billing_documents')
        .select(BillingDocument.columns)
        .eq('customer_id', customerId)
        .order('issued_on', ascending: false)
        .order('created_at', ascending: false);
    return rows.map(BillingDocument.fromJson).toList();
  });

  @override
  Future<String> fileUrl(BillingDocument document) => _guard(
    () =>
        _client.storage.from(bucket).createSignedUrl(document.storagePath, 300),
  );
}

/// Used when the app has no Supabase settings.
class UnavailableBillingRepository implements BillingRepository {
  const UnavailableBillingRepository();

  static const _failure = ServerFailure(
    message: 'Receipts and invoices are unavailable: the app is not connected '
        'to its server.',
  );

  @override
  Future<List<BillingDocument>> getMine(String customerId) =>
      Future.error(_failure);

  @override
  Future<String> fileUrl(BillingDocument document) => Future.error(_failure);
}

final billingRepositoryProvider = Provider<BillingRepository>((ref) {
  if (!Env.isSupabaseConfigured) return const UnavailableBillingRepository();
  return SupabaseBillingRepository(ref.watch(supabaseClientProvider));
});

/// The signed-in customer's receipts and invoices (empty for guests).
final myBillingDocumentsProvider = FutureProvider<List<BillingDocument>>(
  (ref) async {
    final user = await ref.watch(authStateProvider.future);
    if (user == null) return const <BillingDocument>[];
    return ref.watch(billingRepositoryProvider).getMine(user.id);
  },
  isAutoDispose: true,
);
