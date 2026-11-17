import 'package:golden_maids/core/errors/app_failure.dart';
import 'package:golden_maids/features/visas/data/visa_repository.dart';
import 'package:golden_maids/features/visas/domain/visa_application.dart';

/// In-memory visa applications for tests.
class FakeVisaRepository implements VisaRepository {
  FakeVisaRepository({List<VisaApplication>? applications})
    : applications = applications ?? const [];

  List<VisaApplication> applications;

  /// When set, every call fails with this error.
  AppFailure? failure;

  final List<VisaDocument> viewed = [];

  @override
  Future<List<VisaApplication>> getMine(String customerId) async {
    final error = failure;
    if (error != null) throw error;
    return applications;
  }

  @override
  Future<String> viewUrl(VisaDocument document) async {
    viewed.add(document);
    return 'https://files.example.com/${document.storagePath}';
  }

  /// A Company Visa from abroad: contract and entry permit done, the flight
  /// being booked, with the entry permit file.
  static VisaApplication abroad({
    String id = 'v1',
    bool sponsor = false,
    DateTime? expiresOn,
    bool allDone = false,
  }) {
    const order = [
      VisaStep.contractSigned,
      VisaStep.entryPermit,
      VisaStep.flightBooked,
      VisaStep.arrived,
      VisaStep.medicalTest,
      VisaStep.biometrics,
      VisaStep.residenceVisa,
      VisaStep.emiratesId,
    ];
    return VisaApplication(
      id: id,
      hiringRequestId: 'r-$id',
      reference: 'HR-2026-000004',
      journey: VisaJourney.abroad,
      packageName: '2-Year Contract',
      isSponsorVisa: sponsor,
      expiresOn: expiresOn,
      createdAt: DateTime(2026, 11, 10),
      steps: [
        for (var i = 0; i < order.length; i++)
          VisaStepProgress(
            step: order[i],
            position: i + 1,
            status: allDone || i < 2
                ? VisaStepStatus.done
                : i == 2
                ? VisaStepStatus.inProgress
                : VisaStepStatus.waiting,
            date: allDone || i < 2 ? DateTime(2026, 11, 12 + i) : null,
            note: i == 2 && !allDone ? 'Flight options sent to you.' : '',
          ),
      ],
      documents: [
        VisaDocument(
          id: 'd1',
          type: VisaDocumentType.entryPermit,
          storagePath: '$id/entry-permit.pdf',
          fileName: 'entry-permit.pdf',
          createdAt: DateTime(2026, 11, 13),
        ),
      ],
    );
  }
}
