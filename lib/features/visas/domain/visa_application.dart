import '../../candidates/domain/candidate.dart';

/// Where the maid's visa starts from (`visa_applications.route`).
enum VisaJourney {
  abroad('abroad', 'From abroad'),
  inCountry('in_country', 'In the UAE');

  const VisaJourney(this.value, this.label);

  final String value;
  final String label;

  static VisaJourney fromValue(String? value) =>
      value == 'in_country' ? VisaJourney.inCountry : VisaJourney.abroad;
}

/// A step of the visa process, in the order the database creates them.
enum VisaStep {
  contractSigned('contract_signed', 'Contract signed (MOHRE)'),
  entryPermit('entry_permit', 'Entry permit issued'),
  flightBooked('flight_booked', 'Flight booked'),
  arrived('arrived', 'Arrived in the UAE'),
  statusChange('status_change', 'Visa status change'),
  medicalTest('medical_test', 'Medical fitness test'),
  biometrics('biometrics', 'Emirates ID biometrics'),
  residenceVisa('residence_visa', 'Residence visa issued'),
  emiratesId('emirates_id', 'Emirates ID ready');

  const VisaStep(this.value, this.label);

  final String value;
  final String label;

  static VisaStep? fromValue(String? value) {
    for (final step in values) {
      if (step.value == value) return step;
    }
    return null;
  }
}

enum VisaStepStatus {
  waiting('waiting'),
  inProgress('in_progress'),
  done('done');

  const VisaStepStatus(this.value);

  final String value;

  static VisaStepStatus fromValue(String? value) => switch (value) {
    'done' => VisaStepStatus.done,
    'in_progress' => VisaStepStatus.inProgress,
    _ => VisaStepStatus.waiting,
  };
}

class VisaStepProgress {
  const VisaStepProgress({
    required this.step,
    required this.position,
    required this.status,
    this.date,
    this.note = '',
  });

  factory VisaStepProgress.fromJson(Map<String, dynamic> json) {
    final date = json['step_date'] as String?;
    return VisaStepProgress(
      step: VisaStep.fromValue(json['step'] as String?) ??
          VisaStep.contractSigned,
      position: json['position'] as int,
      status: VisaStepStatus.fromValue(json['status'] as String?),
      date: date == null ? null : DateTime.parse(date),
      note: json['note'] as String? ?? '',
    );
  }

  final VisaStep step;
  final int position;
  final VisaStepStatus status;

  /// Only what the agency entered: never estimated.
  final DateTime? date;
  final String note;
}

/// The kinds of file the agency adds to a visa application.
enum VisaDocumentType {
  visa('visa', 'Visa'),
  entryPermit('entry_permit', 'Entry permit'),
  contract('contract', 'Contract'),
  ticket('ticket', 'Flight ticket'),
  medicalBooking('medical_booking', 'Medical test booking'),
  biometricsBooking('biometrics_booking', 'Biometrics booking'),
  emiratesId('emirates_id', 'Emirates ID'),
  other('other', 'Document');

  const VisaDocumentType(this.value, this.label);

  final String value;
  final String label;

  static VisaDocumentType fromValue(String? value) {
    for (final type in values) {
      if (type.value == value) return type;
    }
    return VisaDocumentType.other;
  }
}

class VisaDocument {
  const VisaDocument({
    required this.id,
    required this.type,
    required this.storagePath,
    required this.fileName,
    required this.createdAt,
    this.title = '',
  });

  factory VisaDocument.fromJson(Map<String, dynamic> json) => VisaDocument(
    id: json['id'] as String,
    type: VisaDocumentType.fromValue(json['document_type'] as String?),
    title: json['title'] as String? ?? '',
    storagePath: json['storage_path'] as String,
    fileName: json['file_name'] as String,
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  final String id;
  final VisaDocumentType type;
  final String title;
  final String storagePath;
  final String fileName;
  final DateTime createdAt;

  String get displayName => title.isNotEmpty ? title : type.label;
}

/// How the customer's visa stands, for the badge on its card.
enum VisaState { inProgress, actionNeeded, ready, expiringSoon }

/// A visa application for one of the customer's hiring requests.
class VisaApplication {
  const VisaApplication({
    required this.id,
    required this.hiringRequestId,
    required this.reference,
    required this.journey,
    required this.steps,
    required this.documents,
    required this.createdAt,
    this.packageName = '',
    this.isSponsorVisa = false,
    this.candidate,
    this.expiresOn,
  });

  factory VisaApplication.fromJson(Map<String, dynamic> json) {
    final request = json['hiring_requests'] as Map<String, dynamic>? ?? {};
    final package = request['recruitment_packages'];
    final candidate = request['candidates'];
    final expires = json['visa_expires_on'] as String?;
    final steps =
        (json['visa_application_steps'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(VisaStepProgress.fromJson)
            .toList()
          ..sort((a, b) => a.position.compareTo(b.position));
    final documents =
        (json['visa_documents'] as List<dynamic>? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(VisaDocument.fromJson)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return VisaApplication(
      id: json['id'] as String,
      hiringRequestId: json['hiring_request_id'] as String,
      reference: request['reference'] as String? ?? '',
      journey: VisaJourney.fromValue(json['route'] as String?),
      packageName: package is Map<String, dynamic>
          ? package['name'] as String? ?? ''
          : '',
      isSponsorVisa:
          package is Map<String, dynamic> && package['visa_type'] == 'sponsor',
      candidate: candidate is Map<String, dynamic>
          ? Candidate.fromJson(candidate)
          : null,
      expiresOn: expires == null ? null : DateTime.parse(expires),
      steps: steps,
      documents: documents,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  /// Read for the customer: the request, its package and maid, the steps
  /// and the visa documents.
  static const String columns =
      'id, hiring_request_id, route, visa_expires_on, created_at, '
      'hiring_requests!inner(reference, customer_id, '
      'recruitment_packages(name, visa_type), '
      'candidates(${Candidate.cardColumns})), '
      'visa_application_steps(step, position, status, step_date, note), '
      'visa_documents(id, document_type, title, storage_path, file_name, '
      'created_at)';

  final String id;
  final String hiringRequestId;
  final String reference;
  final VisaJourney journey;
  final String packageName;

  /// GCC Sponsor Visa: the customer sponsors (and sends documents).
  /// Otherwise Golden Maids is the sponsor.
  final bool isSponsorVisa;

  /// The maid (null if she is no longer listed).
  final Candidate? candidate;

  /// Set by the agency once the visa is issued.
  final DateTime? expiresOn;
  final List<VisaStepProgress> steps;
  final List<VisaDocument> documents;
  final DateTime createdAt;

  int get doneCount =>
      steps.where((s) => s.status == VisaStepStatus.done).length;

  /// The step being worked on (or next), null when all are done.
  VisaStepProgress? get currentStep {
    for (final step in steps) {
      if (step.status == VisaStepStatus.inProgress) return step;
    }
    for (final step in steps) {
      if (step.status != VisaStepStatus.done) return step;
    }
    return null;
  }

  bool get isComplete => steps.isNotEmpty && currentStep == null;

  /// Days until the visa expires (negative once expired).
  int? daysToExpiry(DateTime today) {
    final expires = expiresOn;
    if (expires == null) return null;
    final day = DateTime(today.year, today.month, today.day);
    return DateTime(expires.year, expires.month, expires.day)
        .difference(day)
        .inDays;
  }

  /// [missingDocuments]: the sponsor's documents still to send or resend.
  VisaState state(DateTime today, {required bool missingDocuments}) {
    final days = daysToExpiry(today);
    if (days != null && days <= 7) return VisaState.expiringSoon;
    if (isSponsorVisa && missingDocuments && !isComplete) {
      return VisaState.actionNeeded;
    }
    final residence = steps.where((s) => s.step == VisaStep.residenceVisa);
    if (isComplete ||
        residence.any((s) => s.status == VisaStepStatus.done)) {
      return VisaState.ready;
    }
    return VisaState.inProgress;
  }
}
