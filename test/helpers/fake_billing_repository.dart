import 'package:golden_maids/core/errors/app_failure.dart';
import 'package:golden_maids/features/billing/data/billing_repository.dart';
import 'package:golden_maids/features/billing/domain/billing_document.dart';

/// In-memory [BillingRepository].
class FakeBillingRepository implements BillingRepository {
  FakeBillingRepository({List<BillingDocument>? documents})
    : documents = [...?documents];

  final List<BillingDocument> documents;

  /// When set, every call fails with this error.
  AppFailure? failure;

  static BillingDocument receipt() => BillingDocument(
    id: 'b1',
    kind: BillingKind.receipt,
    number: 'R-1001',
    amount: 1500,
    issuedOn: DateTime(2026, 11, 1),
    storagePath: 'u1/r-1001.pdf',
    fileName: 'r-1001.pdf',
    description: 'Monthly fee',
  );

  static BillingDocument invoice() => BillingDocument(
    id: 'b2',
    kind: BillingKind.invoice,
    number: 'INV-42',
    amount: 2000,
    issuedOn: DateTime(2026, 11, 25),
    dueOn: DateTime(2026, 12, 5),
    status: InvoiceStatus.unpaid,
    storagePath: 'u1/inv-42.pdf',
    fileName: 'inv-42.pdf',
  );

  @override
  Future<List<BillingDocument>> getMine(String customerId) async {
    final error = failure;
    if (error != null) throw error;
    return List.of(documents);
  }

  @override
  Future<String> fileUrl(BillingDocument document) async =>
      'https://files.example.com/${document.storagePath}?token=short';
}
