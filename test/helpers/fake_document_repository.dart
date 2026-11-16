import 'dart:typed_data';

import 'package:golden_maids/core/errors/app_failure.dart';
import 'package:golden_maids/features/documents/data/document_repository.dart';
import 'package:golden_maids/features/documents/domain/customer_document.dart';

/// In-memory [DocumentRepository].
class FakeDocumentRepository implements DocumentRepository {
  FakeDocumentRepository({List<CustomerDocument>? documents})
    : documents = [...?documents];

  final List<CustomerDocument> documents;
  final List<({DocumentType type, String name, bool replaced})> uploads = [];
  final List<String> deleted = [];
  AppFailure? failure;
  var _next = 1;

  void _check() {
    final error = failure;
    if (error != null) throw error;
  }

  @override
  Future<List<CustomerDocument>> getMine(String customerId) async {
    _check();
    return List.of(documents);
  }

  @override
  Future<void> upload({
    required String customerId,
    required DocumentType type,
    required PickedDocument file,
    CustomerDocument? existing,
  }) async {
    _check();
    uploads.add((type: type, name: file.name, replaced: existing != null));
    documents
      ..removeWhere((d) => d.type == type)
      ..add(
        CustomerDocument(
          id: existing?.id ?? 'd${_next++}',
          type: type,
          storagePath: '$customerId/${type.value}-${_next++}',
          fileName: file.name,
          mimeType: file.mimeType!,
          sizeBytes: file.bytes.length,
          status: DocumentStatus.submitted,
          uploadedAt: DateTime(2026, 11, 16),
        ),
      );
  }

  @override
  Future<void> delete(CustomerDocument document) async {
    _check();
    deleted.add(document.id);
    documents.removeWhere((d) => d.id == document.id);
  }

  @override
  Future<String> viewUrl(CustomerDocument document) async {
    _check();
    return 'https://example.com/${document.storagePath}';
  }

  static CustomerDocument sample({
    String id = 'd-passport',
    DocumentType type = DocumentType.passport,
    DocumentStatus status = DocumentStatus.submitted,
    String staffNote = '',
  }) => CustomerDocument(
    id: id,
    type: type,
    storagePath: 'u1/${type.value}-1.pdf',
    fileName: '${type.value}.pdf',
    mimeType: 'application/pdf',
    sizeBytes: 240 * 1024,
    status: status,
    staffNote: staffNote,
    uploadedAt: DateTime(2026, 11, 15),
  );

  static PickedDocument file(String name, {int size = 1000}) =>
      PickedDocument(name: name, bytes: Uint8List(size));
}
