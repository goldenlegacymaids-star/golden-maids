import 'dart:typed_data';

/// Documents a customer provides for the GCC Sponsor visa
/// (`customer_documents.document_type`).
enum DocumentType {
  emiratesId('emirates_id', 'Emirates ID'),
  passport('passport', 'Passport copy'),
  salaryCertificate('salary_certificate', 'Salary certificate'),
  marriageCertificate('marriage_certificate', 'Marriage certificate');

  const DocumentType(this.value, this.label);

  final String value;
  final String label;

  static DocumentType? fromValue(String? value) {
    for (final type in values) {
      if (type.value == value) return type;
    }
    return null;
  }
}

/// The agency's review of a document (`customer_documents.status`).
enum DocumentStatus {
  submitted('submitted', 'Under review'),
  approved('approved', 'Approved'),
  needsNewCopy('needs_new_copy', 'Needs a new copy');

  const DocumentStatus(this.value, this.label);

  final String value;
  final String label;

  static DocumentStatus fromValue(String? value) {
    for (final status in values) {
      if (status.value == value) return status;
    }
    return DocumentStatus.submitted;
  }
}

/// A document the customer uploaded (`public.customer_documents`).
/// The file is in the private `customer-documents` bucket.
class CustomerDocument {
  const CustomerDocument({
    required this.id,
    required this.type,
    required this.storagePath,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    required this.status,
    required this.uploadedAt,
    this.staffNote = '',
  });

  factory CustomerDocument.fromJson(Map<String, dynamic> json) =>
      CustomerDocument(
        id: json['id'] as String,
        type:
            DocumentType.fromValue(json['document_type'] as String?) ??
            DocumentType.passport,
        storagePath: json['storage_path'] as String,
        fileName: json['file_name'] as String,
        mimeType: json['mime_type'] as String,
        sizeBytes: (json['size_bytes'] as num).toInt(),
        status: DocumentStatus.fromValue(json['status'] as String?),
        staffNote: (json['staff_note'] as String?) ?? '',
        uploadedAt: DateTime.parse(json['uploaded_at'] as String),
      );

  static const String columns =
      'id, document_type, storage_path, file_name, mime_type, size_bytes, '
      'status, staff_note, uploaded_at';

  final String id;
  final DocumentType type;
  final String storagePath;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final DocumentStatus status;

  /// The agency's reason when a new copy is needed.
  final String staffNote;
  final DateTime uploadedAt;
}

/// A file chosen on the phone, ready to upload.
class PickedDocument {
  const PickedDocument({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;

  /// Largest file accepted (the storage bucket's limit).
  static const int maxBytes = 10 * 1024 * 1024;

  /// `application/pdf`, `image/jpeg` or `image/png`; null for other files.
  String? get mimeType => mimeTypeFor(name);

  /// Why this file cannot be uploaded, or null when it can.
  String? get problem {
    if (mimeType == null) return 'Please choose a PDF, JPG or PNG file.';
    if (bytes.isEmpty) return 'This file is empty.';
    if (bytes.length > maxBytes) {
      return 'This file is larger than 10 MB. Please choose a smaller one.';
    }
    return null;
  }

  static String? mimeTypeFor(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final extension = dot < 0 ? '' : fileName.substring(dot + 1).toLowerCase();
    return switch (extension) {
      'pdf' => 'application/pdf',
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      _ => null,
    };
  }

  /// File extension used in storage (`pdf`, `jpg`, `png`).
  String get storageExtension => switch (mimeType) {
    'application/pdf' => 'pdf',
    'image/png' => 'png',
    _ => 'jpg',
  };
}

/// "240 KB", "1.6 MB".
String fileSizeLabel(int bytes) {
  if (bytes < 1024 * 1024) {
    final kb = (bytes / 1024).ceil();
    return '$kb KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
