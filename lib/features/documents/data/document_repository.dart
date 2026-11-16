import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/supabase_providers.dart';
import '../../authentication/data/auth_providers.dart';
import '../domain/customer_document.dart';

/// The signed-in customer's documents (My Documents).
///
/// Files go to the private `customer-documents` bucket, in a folder named
/// after the customer. Row Level Security lets only the customer and the
/// agency's recruitment staff open them; the database sends a replaced
/// document back for review.
abstract interface class DocumentRepository {
  Future<List<CustomerDocument>> getMine(String customerId);

  /// Uploads [file] as [type], replacing [existing] when given.
  Future<void> upload({
    required String customerId,
    required DocumentType type,
    required PickedDocument file,
    CustomerDocument? existing,
  });

  Future<void> delete(CustomerDocument document);

  /// A link to the file that works for a few minutes.
  Future<String> viewUrl(CustomerDocument document);
}

class SupabaseDocumentRepository implements DocumentRepository {
  SupabaseDocumentRepository(this._client);

  final SupabaseClient _client;

  static const bucket = 'customer-documents';

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(AppFailure.from(error), stackTrace);
    }
  }

  @override
  Future<List<CustomerDocument>> getMine(String customerId) => _guard(() async {
    // Filtered by owner: staff who also use the app see only their own.
    final rows = await _client
        .from('customer_documents')
        .select(CustomerDocument.columns)
        .eq('customer_id', customerId);
    return rows.map(CustomerDocument.fromJson).toList();
  });

  @override
  Future<void> upload({
    required String customerId,
    required DocumentType type,
    required PickedDocument file,
    CustomerDocument? existing,
  }) => _guard(() async {
    final problem = file.problem;
    if (problem != null) throw ValidationFailure(message: problem);
    final mimeType = file.mimeType!;
    final path =
        '$customerId/${type.value}-${DateTime.now().millisecondsSinceEpoch}'
        '.${file.storageExtension}';
    await _client.storage
        .from(bucket)
        .uploadBinary(
          path,
          file.bytes,
          fileOptions: FileOptions(contentType: mimeType),
        );
    final values = {
      'storage_path': path,
      'file_name': file.name.length > 200
          ? file.name.substring(file.name.length - 200)
          : file.name,
      'mime_type': mimeType,
      'size_bytes': file.bytes.length,
    };
    try {
      if (existing == null) {
        await _client.from('customer_documents').insert({
          'document_type': type.value,
          ...values,
        });
      } else {
        await _client
            .from('customer_documents')
            .update(values)
            .eq('id', existing.id)
            .select('id')
            .single();
      }
    } catch (_) {
      // Keep storage tidy if the record could not be saved.
      await _removeQuietly(path);
      rethrow;
    }
    if (existing != null) await _removeQuietly(existing.storagePath);
  });

  @override
  Future<void> delete(CustomerDocument document) => _guard(() async {
    await _client
        .from('customer_documents')
        .delete()
        .eq('id', document.id)
        .select('id')
        .single();
    await _removeQuietly(document.storagePath);
  });

  @override
  Future<String> viewUrl(CustomerDocument document) => _guard(
    () => _client.storage.from(bucket).createSignedUrl(document.storagePath, 300),
  );

  Future<void> _removeQuietly(String path) async {
    try {
      await _client.storage.from(bucket).remove([path]);
    } on Object {
      // A leftover file is harmless; the record is what the app shows.
    }
  }
}

/// Used when the app has no Supabase settings.
class UnavailableDocumentRepository implements DocumentRepository {
  const UnavailableDocumentRepository();

  static const _failure = ServerFailure(
    message:
        'Documents cannot be loaded: the app is not connected to its server.',
  );

  @override
  Future<List<CustomerDocument>> getMine(String customerId) =>
      Future.error(_failure);

  @override
  Future<void> upload({
    required String customerId,
    required DocumentType type,
    required PickedDocument file,
    CustomerDocument? existing,
  }) => Future.error(_failure);

  @override
  Future<void> delete(CustomerDocument document) => Future.error(_failure);

  @override
  Future<String> viewUrl(CustomerDocument document) => Future.error(_failure);
}

final documentRepositoryProvider = Provider<DocumentRepository>((ref) {
  if (!Env.isSupabaseConfigured) return const UnavailableDocumentRepository();
  return SupabaseDocumentRepository(ref.watch(supabaseClientProvider));
});

/// The signed-in customer's documents (empty for guests).
final myDocumentsProvider = FutureProvider<List<CustomerDocument>>((ref) async {
  final user = await ref.watch(authStateProvider.future);
  if (user == null) return const <CustomerDocument>[];
  return ref.watch(documentRepositoryProvider).getMine(user.id);
});

/// Opens the phone's file chooser for a PDF, JPG or PNG; null if cancelled.
typedef DocumentPicker = Future<PickedDocument?> Function();

final documentPickerProvider = Provider<DocumentPicker>(
  (ref) => () async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
    );
    if (file == null) return null;
    return PickedDocument(name: file.name, bytes: await file.readAsBytes());
  },
);
