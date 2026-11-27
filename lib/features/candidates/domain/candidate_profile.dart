import 'candidate.dart';

/// A language a candidate speaks (`public.candidate_languages`).
class CandidateLanguage {
  const CandidateLanguage({required this.language, this.proficiency = 'good'});

  factory CandidateLanguage.fromJson(Map<String, dynamic> json) {
    return CandidateLanguage(
      language: json['language'] as String,
      proficiency: json['proficiency'] as String? ?? 'good',
    );
  }

  final String language;

  /// `basic`, `good` or `fluent`.
  final String proficiency;

  String get proficiencyLabel => switch (proficiency) {
    'basic' => 'Basic',
    'fluent' => 'Fluent',
    _ => 'Good',
  };
}

/// A previous job (`public.candidate_experience`).
class CandidateExperience {
  const CandidateExperience({
    required this.country,
    required this.role,
    required this.startYear,
    this.endYear,
    this.description = '',
  });

  factory CandidateExperience.fromJson(Map<String, dynamic> json) {
    return CandidateExperience(
      country: json['country'] as String,
      role: json['role'] as String,
      startYear: json['start_year'] as int,
      endYear: json['end_year'] as int?,
      description: json['description'] as String? ?? '',
    );
  }

  final String country;
  final String role;
  final int startYear;

  /// Null while still in this job.
  final int? endYear;
  final String description;

  /// `2018 – 2021`, `2021 – Present`
  String get period => '$startYear – ${endYear ?? 'Present'}';
}

/// A document the candidate agreed to share (`public.candidate_documents`).
///
/// Row Level Security returns customer-visible documents only; passports,
/// visas and medical documents can never be visible to customers.
class CandidateDocument {
  const CandidateDocument({
    required this.id,
    required this.type,
    required this.title,
    required this.storagePath,
  });

  factory CandidateDocument.fromJson(Map<String, dynamic> json) {
    return CandidateDocument(
      id: json['id'] as String,
      type: json['document_type'] as String,
      title: json['title'] as String,
      storagePath: json['storage_path'] as String,
    );
  }

  final String id;
  final String type;
  final String title;

  /// Path in the private `candidate-documents` bucket.
  final String storagePath;
}

/// Everything a signed-in customer may see about a candidate.
class CandidateProfile {
  const CandidateProfile({
    required this.candidate,
    this.bio = '',
    this.highestQualification,
    this.religion,
    this.maritalStatus,
    this.skills = const [],
    this.languages = const [],
    this.experience = const [],
    this.packages = const [],
    this.documents = const [],
    this.videoId,
  });

  /// Columns read for the profile, in addition to the card columns.
  static const String profileColumns =
      '${Candidate.cardColumns}, bio, highest_qualification, '
      'marital_status, video_id';

  final Candidate candidate;
  final String bio;
  final String? highestQualification;
  final String? religion;
  final String? maritalStatus;
  final List<CandidateSkill> skills;
  final List<CandidateLanguage> languages;

  /// Most recent first.
  final List<CandidateExperience> experience;

  /// Packages the candidate can be hired under.
  final List<RecruitmentPackage> packages;
  final List<CandidateDocument> documents;

  /// YouTube video ID of her interview (null = none).
  final String? videoId;
}

/// How the customer would like the agency to reply to an enquiry.
enum ContactMethod {
  phone('phone', 'Call'),
  whatsapp('whatsapp', 'WhatsApp'),
  email('email', 'Email');

  const ContactMethod(this.value, this.label);

  final String value;
  final String label;
}

/// A "Request Info" message about a candidate (`public.candidate_enquiries`).
class CandidateEnquiry {
  const CandidateEnquiry({
    required this.candidateId,
    required this.name,
    required this.phone,
    required this.message,
    this.email,
    this.contactMethod = ContactMethod.phone,
  });

  final String candidateId;
  final String name;
  final String phone;
  final String? email;
  final String message;
  final ContactMethod contactMethod;

  Map<String, dynamic> toInsertJson() => {
    'candidate_id': candidateId,
    'customer_name': name,
    'customer_phone': phone,
    'customer_email': email,
    'message': message,
    'contact_method': contactMethod.value,
  };
}
