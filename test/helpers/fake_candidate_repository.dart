import 'package:golden_maids/core/errors/app_failure.dart';
import 'package:golden_maids/features/candidates/data/candidate_repository.dart';
import 'package:golden_maids/features/candidates/domain/candidate.dart';
import 'package:golden_maids/features/candidates/domain/candidate_profile.dart';

/// In-memory [CandidateRepository] that filters like the real one.
class FakeCandidateRepository implements CandidateRepository {
  FakeCandidateRepository({
    List<Candidate>? candidates,
    Map<String, Set<CandidateSkill>>? skills,
    Map<String, Set<String>>? packagesByCandidate,
    Map<String, String>? videos,
  }) : videos = videos ?? const {},
       candidates = candidates ?? defaultCandidates,
       skills = skills ?? defaultSkills,
       packagesByCandidate = packagesByCandidate ?? defaultPackagesByCandidate;

  /// YouTube video IDs of video interviews, by candidate.
  final Map<String, String> videos;

  static const defaultCandidates = [
    Candidate(
      id: 'k1',
      code: 'GM-00001',
      displayName: 'Wanjiru Kamau',
      nationality: 'Kenya',
      age: 34,
      yearsExperience: 6,
      expectedSalary: 1800,
      isFeatured: true,
      isTest: true,
      religion: 'Christian',
    ),
    Candidate(
      id: 'm1',
      code: 'GM-00002',
      displayName: 'Thandar Aung',
      nationality: 'Myanmar',
      age: 31,
      designation: 'Nanny',
      yearsExperience: 4,
      expectedSalary: 1600,
      availability: CandidateAvailability.reserved,
      isFeatured: true,
      isTest: true,
      location: MaidLocation.outsideUae,
    ),
    Candidate(
      id: 'p1',
      code: 'GM-00003',
      displayName: 'Maria Santos',
      nationality: 'Philippines',
      age: 38,
      designation: 'Housekeeper',
      yearsExperience: 9,
      expectedSalary: 2200,
      isFeatured: true,
      isTest: true,
    ),
    // Name not allowed to be shown: the code is shown instead.
    Candidate(
      id: 'e1',
      code: 'GM-00004',
      nationality: 'Ethiopia',
      age: 27,
      yearsExperience: 2,
    ),
  ];

  static const defaultSkills = {
    'k1': {CandidateSkill.cleaning, CandidateSkill.cooking},
    'm1': {CandidateSkill.childcare, CandidateSkill.cleaning},
    'p1': {CandidateSkill.cooking, CandidateSkill.elderlyCare},
    'e1': {CandidateSkill.cleaning},
  };

  static const defaultPackages = [
    RecruitmentPackage(
      id: 'pkg-monthly',
      slug: 'live-in-monthly',
      name: 'Full-Time Live-In Maid – Monthly',
      visaType: 'company',
      contractTerm: 'monthly',
      minMonths: 1,
      maxMonths: 11,
    ),
    RecruitmentPackage(
      id: 'pkg-gcc',
      slug: 'two-year-gcc-sponsor',
      name: '2-Year Contract – GCC Sponsor Visa',
      visaType: 'sponsor',
      contractTerm: 'two_year',
      minMonths: 24,
      maxMonths: 24,
      monthStep: 24,
      requiresSponsorNationality: true,
      priceUnit: 'total',
      priceByNationality: true,
      nationalityPrices: {'Kenya': 15000, 'Philippines': 16500},
    ),
  ];

  /// The nationality list, in the database's order.
  static const defaultNationalities = [
    MaidNationality(
      name: 'Kenya',
      code: 'KE',
      arrivalDaysMin: 10,
      arrivalDaysMax: 20,
    ),
    MaidNationality(name: 'Ethiopia', code: 'ET'),
    MaidNationality(name: 'Myanmar', code: 'MM'),
    MaidNationality(name: 'Indonesia', code: 'ID'),
    MaidNationality(name: 'Philippines', code: 'PH'),
    MaidNationality(name: 'Madagascar', code: 'MG'),
  ];

  static const defaultPackagesByCandidate = {
    'k1': {'pkg-monthly', 'pkg-gcc'},
    'm1': {'pkg-monthly'},
    'p1': {'pkg-monthly', 'pkg-gcc'},
    'e1': {'pkg-monthly'},
  };

  final List<Candidate> candidates;
  final Map<String, Set<CandidateSkill>> skills;
  final Map<String, Set<String>> packagesByCandidate;

  /// When set, every call fails with this error.
  AppFailure? failure;

  /// Filters passed to [search], most recent last.
  final List<CandidateFilter> searches = [];

  void _check() {
    final error = failure;
    if (error != null) throw error;
  }

  @override
  Future<List<Candidate>> getFeatured() async {
    _check();
    return candidates.where((c) => c.isFeatured).toList();
  }

  @override
  Future<List<Candidate>> search(CandidateFilter filter) async {
    _check();
    searches.add(filter);
    final term = filter.query.toLowerCase();
    final results = candidates.where((c) {
      if (filter.availableOnly &&
          c.availability != CandidateAvailability.available) {
        return false;
      }
      if (filter.nationalities.isNotEmpty &&
          !filter.nationalities.contains(c.nationality)) {
        return false;
      }
      if (filter.designation != null && c.designation != filter.designation) {
        return false;
      }
      final packageId = filter.packageId;
      if (packageId != null &&
          !(packagesByCandidate[c.id] ?? const <String>{}).contains(packageId)) {
        return false;
      }
      if (!(skills[c.id] ?? const <CandidateSkill>{}).containsAll(
        filter.skills,
      )) {
        return false;
      }
      final location = filter.location;
      if (location != null && c.location != location) return false;
      final visa = filter.visa;
      if (visa != null) {
        final onVisa = defaultPackages
            .where((p) => p.visaType == visa.value)
            .map((p) => p.id)
            .toSet();
        if ((packagesByCandidate[c.id] ?? const <String>{})
            .intersection(onVisa)
            .isEmpty) {
          return false;
        }
      }
      return term.isEmpty ||
          c.code.toLowerCase().contains(term) ||
          (c.displayName ?? '').toLowerCase().contains(term);
    }).toList();
    if (filter.sort == CandidateSort.mostExperienced) {
      results.sort((a, b) => b.yearsExperience.compareTo(a.yearsExperience));
    }
    return results;
  }

  @override
  Future<List<RecruitmentPackage>> getPackages() async {
    _check();
    return defaultPackages;
  }

  @override
  Future<List<MaidNationality>> getNationalities() async {
    _check();
    return defaultNationalities;
  }

  @override
  Future<List<String>> getDesignations() async {
    _check();
    return candidates.map((c) => c.designation).toSet().toList()..sort();
  }

  @override
  String? photoUrl(String? path) => null;

  // --- Profile -----------------------------------------------------------

  /// Extra profile details for Wanjiru (k1); others get the basics.
  static const wanjiruDetails = (
    bio: 'TEST PROFILE. Hard-working housemaid.',
    religion: 'Christian',
    maritalStatus: 'Single',
    qualification: 'Secondary school',
  );

  /// Shareable documents per candidate (customer-visible only).
  final Map<String, List<CandidateDocument>> documents = {
    'k1': const [
      CandidateDocument(
        id: 'd1',
        type: 'certificate',
        title: 'Housekeeping certificate',
        storagePath: 'k1/certificate.pdf',
      ),
    ],
  };

  @override
  Future<CandidateProfile> getProfile(String candidateId) async {
    _check();
    final candidate = candidates.firstWhere(
      (c) => c.id == candidateId,
      orElse: () => throw const NotFoundFailure(),
    );
    final isWanjiru = candidateId == 'k1';
    return CandidateProfile(
      candidate: candidate,
      bio: isWanjiru ? wanjiruDetails.bio : '',
      religion: isWanjiru ? wanjiruDetails.religion : null,
      maritalStatus: isWanjiru ? wanjiruDetails.maritalStatus : null,
      highestQualification: isWanjiru ? wanjiruDetails.qualification : null,
      videoId: videos[candidateId],
      skills: (skills[candidateId] ?? const <CandidateSkill>{}).toList(),
      languages: isWanjiru
          ? const [
              CandidateLanguage(language: 'English', proficiency: 'fluent'),
              CandidateLanguage(language: 'Swahili', proficiency: 'fluent'),
            ]
          : const [],
      experience: isWanjiru
          ? const [
              CandidateExperience(
                country: 'United Arab Emirates',
                role: 'Housemaid',
                startYear: 2021,
                endYear: 2024,
              ),
              CandidateExperience(
                country: 'Saudi Arabia',
                role: 'Housemaid',
                startYear: 2018,
                endYear: 2021,
              ),
            ]
          : const [],
      packages: [
        for (final package in defaultPackages)
          if ((packagesByCandidate[candidateId] ?? const <String>{})
              .contains(package.id))
            package,
      ],
      documents: documents[candidateId] ?? const [],
    );
  }

  /// Documents opened, by storage path.
  final List<String> openedDocuments = [];

  @override
  Future<String> documentUrl(String storagePath) async {
    _check();
    openedDocuments.add(storagePath);
    return 'https://example.com/signed/$storagePath';
  }

  // --- Favourites --------------------------------------------------------

  final Set<String> favouriteIds = {};

  @override
  Future<Set<String>> getFavouriteIds() async {
    _check();
    return {...favouriteIds};
  }

  @override
  Future<void> setFavourite(String candidateId, {required bool saved}) async {
    _check();
    if (saved) {
      favouriteIds.add(candidateId);
    } else {
      favouriteIds.remove(candidateId);
    }
  }

  @override
  Future<List<Candidate>> getFavourites() async {
    _check();
    return candidates.where((c) => favouriteIds.contains(c.id)).toList();
  }

  // --- Enquiries ---------------------------------------------------------

  final List<CandidateEnquiry> enquiries = [];

  /// When set, sending an enquiry fails with this error.
  AppFailure? enquiryFailure;

  @override
  Future<String> sendEnquiry(CandidateEnquiry enquiry) async {
    _check();
    final error = enquiryFailure;
    if (error != null) throw error;
    enquiries.add(enquiry);
    return 'EQ-2026-${enquiries.length.toString().padLeft(6, '0')}';
  }
}
