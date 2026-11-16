import '../../candidates/domain/candidate.dart';
import '../../candidates/domain/candidate_profile.dart';

/// Where a hiring request is in the process (`hiring_requests.status`).
enum HiringStatus {
  submitted('submitted', 'Submitted'),
  underReview('under_review', 'Under review'),
  shortlisted('shortlisted', 'Shortlisted'),
  interviewScheduled('interview_scheduled', 'Interview scheduled'),
  offerAccepted('offer_accepted', 'Offer accepted'),
  visaProcessing('visa_processing', 'Visa processing'),
  completed('completed', 'Completed'),
  cancelled('cancelled', 'Cancelled'),
  rejected('rejected', 'Not successful');

  const HiringStatus(this.value, this.label);

  final String value;
  final String label;

  static HiringStatus fromValue(String? value) {
    for (final status in values) {
      if (status.value == value) return status;
    }
    return HiringStatus.submitted;
  }

  /// Customers may cancel until the agency starts shortlisting
  /// (the database enforces the same rule).
  bool get canCancel =>
      this == HiringStatus.submitted || this == HiringStatus.underReview;

  bool get isClosed =>
      this == HiringStatus.completed ||
      this == HiringStatus.cancelled ||
      this == HiringStatus.rejected;
}

/// A customer's request to hire a domestic worker (`public.hiring_requests`).
class HiringRequest {
  const HiringRequest({
    required this.id,
    required this.reference,
    required this.packageId,
    required this.durationMonths,
    required this.status,
    required this.createdAt,
    required this.customerName,
    required this.customerPhone,
    required this.emirate,
    this.packageName = '',
    this.sponsorNationality,
    this.candidateId,
    this.candidate,
    this.customerEmail,
    this.householdSize,
    this.hasChildren = false,
    this.hasElderly = false,
    this.hasPets = false,
    this.preferredStartDate,
    this.requirements = '',
    this.contactMethod = ContactMethod.phone,
    this.preferredNationality,
    this.quotedPrice,
    this.quotedPriceUnit,
  });

  factory HiringRequest.fromJson(Map<String, dynamic> json) {
    final package = json['recruitment_packages'];
    final candidate = json['candidates'];
    final start = json['preferred_start_date'] as String?;
    return HiringRequest(
      id: json['id'] as String,
      reference: json['reference'] as String,
      packageId: json['package_id'] as String,
      packageName: package is Map<String, dynamic>
          ? package['name'] as String? ?? ''
          : '',
      durationMonths: json['duration_months'] as int,
      sponsorNationality: json['sponsor_nationality'] as String?,
      candidateId: json['candidate_id'] as String?,
      candidate: candidate is Map<String, dynamic>
          ? Candidate.fromJson(candidate)
          : null,
      status: HiringStatus.fromValue(json['status'] as String?),
      createdAt: DateTime.parse(json['created_at'] as String),
      customerName: json['customer_name'] as String,
      customerPhone: json['customer_phone'] as String,
      customerEmail: json['customer_email'] as String?,
      emirate: json['emirate'] as String,
      householdSize: json['household_size'] as int?,
      hasChildren: json['has_children'] as bool? ?? false,
      hasElderly: json['has_elderly'] as bool? ?? false,
      hasPets: json['has_pets'] as bool? ?? false,
      preferredStartDate: start == null ? null : DateTime.tryParse(start),
      requirements: json['requirements'] as String? ?? '',
      preferredNationality: json['preferred_nationality'] as String?,
      quotedPrice: (json['quoted_price'] as num?)?.toDouble(),
      quotedPriceUnit: json['quoted_price_unit'] as String?,
      contactMethod: ContactMethod.values.firstWhere(
        (m) => m.value == json['contact_method'],
        orElse: () => ContactMethod.phone,
      ),
    );
  }

  /// Columns read for the customer, with the package name and the
  /// candidate's card (null if the candidate is no longer listed).
  static const String columns =
      'id, reference, package_id, duration_months, sponsor_nationality, '
      'candidate_id, status, created_at, customer_name, customer_phone, '
      'customer_email, emirate, household_size, has_children, has_elderly, '
      'has_pets, preferred_start_date, requirements, contact_method, '
      'preferred_nationality, quoted_price, quoted_price_unit, '
      'recruitment_packages(name), candidates(${Candidate.cardColumns})';

  final String id;

  /// e.g. `HR-2026-000001`.
  final String reference;
  final String packageId;
  final String packageName;
  final int durationMonths;

  /// ISO code of the sponsor's GCC nationality (sponsor packages only).
  final String? sponsorNationality;

  /// Null when the customer asked the agency to recommend someone.
  final String? candidateId;
  final Candidate? candidate;
  final HiringStatus status;
  final DateTime createdAt;
  final String customerName;
  final String customerPhone;
  final String? customerEmail;
  final String emirate;
  final int? householdSize;
  final bool hasChildren;
  final bool hasElderly;
  final bool hasPets;
  final DateTime? preferredStartDate;
  final String requirements;
  final ContactMethod contactMethod;

  /// The maid's nationality (chosen maid, or asked for).
  final String? preferredNationality;

  /// The price shown when the request was sent (null = on request).
  final double? quotedPrice;

  /// `per_month` or `total`.
  final String? quotedPriceUnit;

  /// The same request with a new [status].
  HiringRequest withStatus(HiringStatus status) => HiringRequest(
    id: id,
    reference: reference,
    packageId: packageId,
    packageName: packageName,
    durationMonths: durationMonths,
    sponsorNationality: sponsorNationality,
    candidateId: candidateId,
    candidate: candidate,
    status: status,
    createdAt: createdAt,
    customerName: customerName,
    customerPhone: customerPhone,
    customerEmail: customerEmail,
    emirate: emirate,
    householdSize: householdSize,
    hasChildren: hasChildren,
    hasElderly: hasElderly,
    hasPets: hasPets,
    preferredStartDate: preferredStartDate,
    requirements: requirements,
    contactMethod: contactMethod,
    preferredNationality: preferredNationality,
    quotedPrice: quotedPrice,
    quotedPriceUnit: quotedPriceUnit,
  );

  /// The maid's name or code, or "Agency recommendation".
  String get maidLabel =>
      candidate?.title ??
      (candidateId == null ? 'Agency recommendation' : 'Candidate');
}

/// A status change shown on the request's timeline.
class HiringStatusEvent {
  const HiringStatusEvent({
    required this.status,
    required this.createdAt,
    this.note = '',
  });

  factory HiringStatusEvent.fromJson(Map<String, dynamic> json) {
    return HiringStatusEvent(
      status: HiringStatus.fromValue(json['status'] as String?),
      note: json['note'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final HiringStatus status;
  final String note;
  final DateTime createdAt;
}

/// What the customer fills in before submitting a hiring request.
class HiringDraft {
  const HiringDraft({
    required this.packageId,
    required this.durationMonths,
    required this.name,
    required this.phone,
    required this.emirate,
    this.sponsorNationality,
    this.candidateId,
    this.preferredNationality,
    this.email,
    this.householdSize,
    this.hasChildren = false,
    this.hasElderly = false,
    this.hasPets = false,
    this.preferredStartDate,
    this.requirements = '',
    this.contactMethod = ContactMethod.phone,
  });

  final String packageId;
  final int durationMonths;
  final String? sponsorNationality;
  final String? candidateId;

  /// The maid nationality asked for when the agency recommends the maid.
  final String? preferredNationality;
  final String name;
  final String phone;
  final String? email;
  final String emirate;
  final int? householdSize;
  final bool hasChildren;
  final bool hasElderly;
  final bool hasPets;
  final DateTime? preferredStartDate;
  final String requirements;
  final ContactMethod contactMethod;

  Map<String, dynamic> toInsertJson() {
    final start = preferredStartDate;
    return {
      'package_id': packageId,
      'duration_months': durationMonths,
      'sponsor_nationality': sponsorNationality,
      'candidate_id': candidateId,
      'preferred_nationality': preferredNationality,
      'customer_name': name,
      'customer_phone': phone,
      'customer_email': email,
      'emirate': emirate,
      'household_size': householdSize,
      'has_children': hasChildren,
      'has_elderly': hasElderly,
      'has_pets': hasPets,
      'preferred_start_date': start == null
          ? null
          : '${start.year.toString().padLeft(4, '0')}-'
                '${start.month.toString().padLeft(2, '0')}-'
                '${start.day.toString().padLeft(2, '0')}',
      'requirements': requirements,
      'contact_method': contactMethod.value,
    };
  }
}

/// Durations the customer can choose for [package], in months.
List<int> durationOptions(RecruitmentPackage package) => [
  for (
    var months = package.minMonths;
    months <= package.maxMonths;
    months += package.monthStep
  )
    months,
];
