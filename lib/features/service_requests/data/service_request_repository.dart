import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/supabase_providers.dart';
import '../../authentication/data/auth_providers.dart';
import '../../documents/domain/customer_document.dart' show PickedDocument;
import '../domain/service_request.dart';

/// The signed-in customer's service requests (visa, replacement, NOC, …).
///
/// Row Level Security lets customers read only their own and cancel them
/// only while they are waiting; the database checks the maid, travel
/// details and attachments. Files go to the private `service-request-files`
/// bucket, in a folder named after the request.
abstract interface class ServiceRequestRepository {
  /// Sends a request with its attachments and returns its id.
  Future<String> submit(ServiceRequestDraft draft);

  /// The customer's requests, newest first.
  Future<List<ServiceRequest>> getMine();

  Future<ServiceRequestDetails> getDetails(String id);

  Future<void> cancel(String id);

  Future<void> sendMessage(String requestId, String body);

  Future<void> addFile(String requestId, PickedDocument file);

  /// A link to the file that works for a few minutes.
  Future<String> fileUrl(ServiceRequestFile file);
}

class SupabaseServiceRequestRepository implements ServiceRequestRepository {
  SupabaseServiceRequestRepository(this._client);

  final SupabaseClient _client;

  static const bucket = 'service-request-files';

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
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
  Future<String> submit(ServiceRequestDraft draft) => _guard(() async {
    final errors = draft.validate();
    if (errors.isNotEmpty) {
      throw ValidationFailure(message: errors.values.first);
    }
    for (final file in draft.attachments) {
      final problem = file.problem;
      if (problem != null) throw ValidationFailure(message: problem);
    }
    final row = await _client
        .from('service_requests')
        .insert(draft.toInsertJson())
        .select('id')
        .single();
    final id = row['id'] as String;
    // The request is sent even if an attachment fails; the customer can
    // add it again from the request page.
    for (final file in draft.attachments) {
      await _upload(id, file);
    }
    return id;
  });

  @override
  Future<List<ServiceRequest>> getMine() => _guard(() async {
    // Staff accounts can read every request, so the customer's own are
    // selected explicitly.
    final rows = await _client
        .from('service_requests')
        .select(ServiceRequest.columns)
        .eq('customer_id', _userId())
        .order('created_at', ascending: false);
    return rows.map(ServiceRequest.fromJson).toList();
  });

  @override
  Future<ServiceRequestDetails> getDetails(String id) => _guard(() async {
    final row = await _client
        .from('service_requests')
        .select(ServiceRequest.columns)
        .eq('id', id)
        .eq('customer_id', _userId())
        .single();
    final messages = await _client
        .from('service_request_messages')
        .select(ServiceRequestMessage.columns)
        .eq('request_id', id)
        .order('created_at', ascending: true);
    final files = await _client
        .from('service_request_files')
        .select(ServiceRequestFile.columns)
        .eq('request_id', id)
        .order('created_at', ascending: true);
    return ServiceRequestDetails(
      request: ServiceRequest.fromJson(row),
      messages: messages.map(ServiceRequestMessage.fromJson).toList(),
      files: files.map(ServiceRequestFile.fromJson).toList(),
    );
  });

  @override
  Future<void> cancel(String id) => _guard(() async {
    final rows = await _client
        .from('service_requests')
        .update({'status': ServiceRequestStatus.cancelled.value})
        .eq('id', id)
        .select('id');
    if (rows.isEmpty) throw const NotFoundFailure();
  });

  @override
  Future<void> sendMessage(String requestId, String body) => _guard(() async {
    final text = body.trim();
    if (text.isEmpty) {
      throw const ValidationFailure(message: 'Write a message first.');
    }
    if (text.length > 1000) {
      throw const ValidationFailure(
        message: 'Please keep it under 1,000 characters.',
      );
    }
    await _client.from('service_request_messages').insert({
      'request_id': requestId,
      'body': text,
    });
  });

  @override
  Future<void> addFile(String requestId, PickedDocument file) =>
      _guard(() async {
        final problem = file.problem;
        if (problem != null) throw ValidationFailure(message: problem);
        await _upload(requestId, file);
      });

  Future<void> _upload(String requestId, PickedDocument file) async {
    final mimeType = file.mimeType!;
    final path =
        '$requestId/${DateTime.now().millisecondsSinceEpoch}'
        '.${file.storageExtension}';
    await _client.storage
        .from(bucket)
        .uploadBinary(
          path,
          file.bytes,
          fileOptions: FileOptions(contentType: mimeType),
        );
    try {
      await _client.from('service_request_files').insert({
        'request_id': requestId,
        'storage_path': path,
        'file_name': file.name.length > 200
            ? file.name.substring(file.name.length - 200)
            : file.name,
        'mime_type': mimeType,
        'size_bytes': file.bytes.length,
      });
    } catch (_) {
      // Keep storage tidy if the record could not be saved.
      try {
        await _client.storage.from(bucket).remove([path]);
      } on Object {
        // A leftover file is harmless; the record is what the app shows.
      }
      rethrow;
    }
  }

  @override
  Future<String> fileUrl(ServiceRequestFile file) => _guard(
    () => _client.storage.from(bucket).createSignedUrl(file.storagePath, 300),
  );
}

/// Used when the app has no Supabase settings.
class UnavailableServiceRequestRepository implements ServiceRequestRepository {
  const UnavailableServiceRequestRepository();

  static const _failure = ServerFailure(
    message: 'Requests are unavailable: the app is not connected to its '
        'server.',
  );

  @override
  Future<String> submit(ServiceRequestDraft draft) => Future.error(_failure);

  @override
  Future<List<ServiceRequest>> getMine() => Future.error(_failure);

  @override
  Future<ServiceRequestDetails> getDetails(String id) => Future.error(_failure);

  @override
  Future<void> cancel(String id) => Future.error(_failure);

  @override
  Future<void> sendMessage(String requestId, String body) =>
      Future.error(_failure);

  @override
  Future<void> addFile(String requestId, PickedDocument file) =>
      Future.error(_failure);

  @override
  Future<String> fileUrl(ServiceRequestFile file) => Future.error(_failure);
}

final serviceRequestRepositoryProvider = Provider<ServiceRequestRepository>((
  ref,
) {
  if (!Env.isSupabaseConfigured) {
    return const UnavailableServiceRequestRepository();
  }
  return SupabaseServiceRequestRepository(ref.watch(supabaseClientProvider));
});

/// The signed-in customer's service requests (empty for guests).
final myServiceRequestsProvider = FutureProvider<List<ServiceRequest>>(
  (ref) async {
    final user = await ref.watch(authStateProvider.future);
    if (user == null) return const <ServiceRequest>[];
    return ref.watch(serviceRequestRepositoryProvider).getMine();
  },
  isAutoDispose: true,
);

final serviceRequestDetailsProvider =
    FutureProvider.family<ServiceRequestDetails, String>(
      (ref, id) => ref.watch(serviceRequestRepositoryProvider).getDetails(id),
      isAutoDispose: true,
    );
