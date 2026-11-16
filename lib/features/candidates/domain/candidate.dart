/// A nationality the agency recruits from (`public.maid_nationalities`).
/// Administrators manage the list; [code] is the ISO country code (KE) used
/// for the flag.
class MaidNationality {
  const MaidNationality({required this.name, required this.code});

  factory MaidNationality.fromJson(Map<String, dynamic> json) {
    return MaidNationality(
      name: json['name'] as String,
      code: json['code'] as String,
    );
  }

  static const String columns = 'name, code';

  final String name;
  final String code;
}

/// Skills a candidate can have (`public.candidate_skills.skill`).
enum CandidateSkill {
  cleaning('cleaning', 'Cleaning'),
  cooking('cooking', 'Cooking'),
  childcare('childcare', 'Childcare'),
  elderlyCare('elderly_care', 'Elderly care'),
  laundry('laundry', 'Laundry'),
  ironing('ironing', 'Ironing'),
  petCare('pet_care', 'Pet care'),
  householdManagement('household_management', 'Household management'),
  driving('driving', 'Driving');

  const CandidateSkill(this.value, this.label);

  final String value;
  final String label;

  static CandidateSkill? fromValue(String? value) {
    for (final skill in values) {
      if (skill.value == value) return skill;
    }
    return null;
  }
}

/// Whether a candidate can be hired (`availability_status`).
enum CandidateAvailability {
  available('available', 'Available'),
  reserved('reserved', 'Reserved'),
  hired('hired', 'Hired'),
  unavailable('unavailable', 'Unavailable');

  const CandidateAvailability(this.value, this.label);

  final String value;
  final String label;

  static CandidateAvailability fromValue(String? value) {
    for (final status in values) {
      if (status.value == value) return status;
    }
    return CandidateAvailability.unavailable;
  }
}

/// A domestic-worker candidate as shown on cards (`public.candidates`).
///
/// Only the card columns are read here, because guests may read nothing
/// else. The full profile is loaded separately for signed-in users.
class Candidate {
  const Candidate({
    required this.id,
    required this.code,
    required this.nationality,
    this.displayName,
    this.photoPath,
    this.age,
    this.designation = 'Housemaid',
    this.accommodation = 'live_in',
    this.yearsExperience = 0,
    this.expectedSalary,
    this.availability = CandidateAvailability.available,
    this.availableFrom,
    this.isFeatured = false,
    this.isTest = false,
  });

  factory Candidate.fromJson(Map<String, dynamic> json) {
    final availableFrom = json['available_from'] as String?;
    return Candidate(
      id: json['id'] as String,
      code: json['code'] as String,
      nationality: json['nationality'] as String,
      displayName: json['display_name'] as String?,
      photoPath: json['photo_path'] as String?,
      age: json['age'] as int?,
      designation: json['designation'] as String? ?? 'Housemaid',
      accommodation: json['accommodation'] as String? ?? 'live_in',
      yearsExperience: json['years_experience'] as int? ?? 0,
      expectedSalary: (json['expected_salary'] as num?)?.toDouble(),
      availability: CandidateAvailability.fromValue(
        json['availability_status'] as String?,
      ),
      availableFrom: availableFrom == null
          ? null
          : DateTime.tryParse(availableFrom),
      isFeatured: json['is_featured'] as bool? ?? false,
      isTest: json['is_test'] as bool? ?? false,
    );
  }

  /// Columns guests are allowed to read (see the recruitment migration).
  static const String cardColumns =
      'id, code, display_name, photo_path, nationality, age, designation, '
      'accommodation, years_experience, expected_salary, availability_status, '
      'available_from, is_featured, is_test, created_at';

  final String id;

  /// Reference such as `GM-00001`.
  final String code;
  final String nationality;

  /// Set only when an administrator allows the name to be shown.
  final String? displayName;

  /// Path in the public `candidate-photos` bucket.
  final String? photoPath;
  final int? age;
  final String designation;

  /// `live_in` or `live_out`.
  final String accommodation;
  final int yearsExperience;

  /// Expected monthly salary in AED.
  final double? expectedSalary;
  final CandidateAvailability availability;
  final DateTime? availableFrom;
  final bool isFeatured;

  /// Test record (deleted before launch).
  final bool isTest;

  /// The name when allowed, otherwise the candidate code.
  String get title => displayName ?? code;
}

/// A hiring package (`public.recruitment_packages`).
class RecruitmentPackage {
  const RecruitmentPackage({
    required this.id,
    required this.slug,
    required this.name,
    required this.visaType,
    required this.contractTerm,
    required this.minMonths,
    required this.maxMonths,
    this.description = '',
    this.monthStep = 1,
    this.requiresSponsorNationality = false,
    this.price,
    this.priceUnit,
    this.priceByNationality = false,
    this.nationalityPrices = const {},
  });

  factory RecruitmentPackage.fromJson(Map<String, dynamic> json) {
    final prices = json['recruitment_package_prices'] as List<dynamic>? ?? [];
    return RecruitmentPackage(
      id: json['id'] as String,
      slug: json['slug'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      visaType: json['visa_type'] as String,
      contractTerm: json['contract_term'] as String,
      minMonths: json['min_months'] as int,
      maxMonths: json['max_months'] as int,
      monthStep: json['month_step'] as int? ?? 1,
      requiresSponsorNationality:
          json['requires_sponsor_nationality'] as bool? ?? false,
      price: (json['price'] as num?)?.toDouble(),
      priceUnit: json['price_unit'] as String?,
      priceByNationality: json['price_by_nationality'] as bool? ?? false,
      nationalityPrices: {
        for (final row in prices.cast<Map<String, dynamic>>())
          row['nationality'] as String: (row['price'] as num).toDouble(),
      },
    );
  }

  static const String columns =
      'id, slug, name, description, visa_type, contract_term, min_months, '
      'max_months, month_step, requires_sponsor_nationality, price, '
      'price_unit, price_by_nationality, '
      'recruitment_package_prices(nationality, price)';

  final String id;
  final String slug;
  final String name;
  final String description;

  /// `company` (company visa) or `sponsor` (GCC sponsor visa).
  final String visaType;

  /// `monthly`, `yearly` or `two_year`.
  final String contractTerm;
  final int minMonths;
  final int maxMonths;
  final int monthStep;
  final bool requiresSponsorNationality;

  /// Set by administrators; null means "Price on request". Not used when
  /// [priceByNationality] is true.
  final double? price;

  /// `per_month` or `total`.
  final String? priceUnit;

  /// The price depends on the maid's nationality (2-Year GCC Sponsor
  /// package: a one-off recruitment cost).
  final bool priceByNationality;

  /// Nationality name → price, for [priceByNationality] packages.
  final Map<String, double> nationalityPrices;

  /// The price for a maid of [nationality] (null = on request, or unknown
  /// nationality).
  double? priceFor(String? nationality) {
    if (!priceByNationality) return price;
    return nationality == null ? null : nationalityPrices[nationality];
  }

  /// Short label for filter chips.
  String get shortName => switch (contractTerm) {
    'monthly' => 'Monthly',
    'yearly' => 'Yearly',
    'two_year' => '2-Year GCC',
    _ => name,
  };
}

/// How the candidate directory is sorted.
enum CandidateSort {
  newest('Newest'),
  mostExperienced('Most experienced');

  const CandidateSort(this.label);

  final String label;
}

/// Search and filter settings for the candidate directory.
class CandidateFilter {
  const CandidateFilter({
    this.query = '',
    this.nationalities = const {},
    this.designation,
    this.packageId,
    this.skills = const {},
    this.availableOnly = false,
    this.sort = CandidateSort.newest,
  });

  /// Name or candidate code.
  final String query;
  final Set<String> nationalities;
  final String? designation;
  final String? packageId;

  /// Candidates must have every selected skill.
  final Set<CandidateSkill> skills;

  /// Hide reserved candidates.
  final bool availableOnly;
  final CandidateSort sort;

  /// Number of filters set in the filter sheet (not search or sort).
  int get activeCount =>
      nationalities.length +
      (designation == null ? 0 : 1) +
      (packageId == null ? 0 : 1) +
      skills.length +
      (availableOnly ? 1 : 0);

  CandidateFilter copyWith({
    String? query,
    Set<String>? nationalities,
    String? Function()? designation,
    String? Function()? packageId,
    Set<CandidateSkill>? skills,
    bool? availableOnly,
    CandidateSort? sort,
  }) {
    return CandidateFilter(
      query: query ?? this.query,
      nationalities: nationalities ?? this.nationalities,
      designation: designation == null ? this.designation : designation(),
      packageId: packageId == null ? this.packageId : packageId(),
      skills: skills ?? this.skills,
      availableOnly: availableOnly ?? this.availableOnly,
      sort: sort ?? this.sort,
    );
  }

  /// The same filters with the search text and sort kept.
  CandidateFilter cleared() => CandidateFilter(query: query, sort: sort);

  @override
  bool operator ==(Object other) =>
      other is CandidateFilter &&
      other.query == query &&
      _sameSet(other.nationalities, nationalities) &&
      other.designation == designation &&
      other.packageId == packageId &&
      _sameSet(other.skills, skills) &&
      other.availableOnly == availableOnly &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(
    query,
    Object.hashAllUnordered(nationalities),
    designation,
    packageId,
    Object.hashAllUnordered(skills),
    availableOnly,
    sort,
  );

  static bool _sameSet<T>(Set<T> a, Set<T> b) =>
      a.length == b.length && a.containsAll(b);
}
