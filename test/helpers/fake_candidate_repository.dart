import 'package:golden_maids/core/errors/app_failure.dart';
import 'package:golden_maids/features/candidates/data/candidate_repository.dart';
import 'package:golden_maids/features/candidates/domain/candidate.dart';

/// In-memory [CandidateRepository] that filters like the real one.
class FakeCandidateRepository implements CandidateRepository {
  FakeCandidateRepository({
    List<Candidate>? candidates,
    Map<String, Set<CandidateSkill>>? skills,
    Map<String, Set<String>>? packagesByCandidate,
  }) : candidates = candidates ?? defaultCandidates,
       skills = skills ?? defaultSkills,
       packagesByCandidate = packagesByCandidate ?? defaultPackagesByCandidate;

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
    ),
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
  Future<List<String>> getDesignations() async {
    _check();
    return candidates.map((c) => c.designation).toSet().toList()..sort();
  }

  @override
  String? photoUrl(String? path) => null;
}
