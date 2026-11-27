/// `customer_billing_documents.kind`.
enum BillingKind {
  receipt('receipt', 'Receipt'),
  invoice('invoice', 'Invoice');

  const BillingKind(this.value, this.label);

  final String value;
  final String label;

  static BillingKind fromValue(String? value) =>
      value == invoice.value ? invoice : receipt;
}

/// An invoice's status (receipts have none).
enum InvoiceStatus {
  unpaid('unpaid', 'Unpaid'),
  paid('paid', 'Paid'),
  cancelled('cancelled', 'Cancelled');

  const InvoiceStatus(this.value, this.label);

  final String value;
  final String label;

  static InvoiceStatus? fromValue(String? value) {
    for (final status in values) {
      if (status.value == value) return status;
    }
    return null;
  }
}

/// A receipt or invoice the agency added for the customer
/// (`public.customer_billing_documents`); the file is in the private
/// `billing-documents` bucket.
class BillingDocument {
  const BillingDocument({
    required this.id,
    required this.kind,
    required this.number,
    required this.amount,
    required this.issuedOn,
    required this.storagePath,
    required this.fileName,
    this.status,
    this.dueOn,
    this.description = '',
  });

  factory BillingDocument.fromJson(Map<String, dynamic> json) {
    final due = json['due_on'] as String?;
    return BillingDocument(
      id: json['id'] as String,
      kind: BillingKind.fromValue(json['kind'] as String?),
      number: json['number'] as String,
      amount: (json['amount'] as num).toDouble(),
      issuedOn: DateTime.parse(json['issued_on'] as String),
      storagePath: json['storage_path'] as String,
      fileName: json['file_name'] as String,
      status: InvoiceStatus.fromValue(json['status'] as String?),
      dueOn: due == null ? null : DateTime.tryParse(due),
      description: (json['description'] as String?) ?? '',
    );
  }

  static const String columns =
      'id, kind, number, amount, status, issued_on, due_on, description, '
      'storage_path, file_name';

  final String id;
  final BillingKind kind;

  /// The agency's receipt or invoice number.
  final String number;
  final double amount;
  final DateTime issuedOn;
  final String storagePath;
  final String fileName;

  /// Invoices only.
  final InvoiceStatus? status;
  final DateTime? dueOn;
  final String description;
}
