import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/supabase_providers.dart';
import '../../authentication/data/auth_providers.dart';
import '../domain/candidate.dart';
import '../domain/candidate_profile.dart';

/// Read access to the candidate directory.
///
/// Row Level Security returns only published, non-archived candidates to
/// customers and guests, and guests can read the card columns only.
abstract interface class CandidateRepository {
  /// Featured candidates for the Home screen (available or reserved).
  Future<List<Candidate>> getFeatured();

  /// Candidates matching [filter] (hired / unavailable ones are left out).
  Future<List<Candidate>> search(CandidateFilter filter);

  /// Active hiring packages, in display order.
  Future<List<RecruitmentPackage>> getPackages();

  /// Job titles in use (e.g. Housemaid, Nanny), for the filter.
  Future<List<String>> getDesignations();

  /// Public URL of a photo in the `candidate-photos` bucket, or null.
  String? photoUrl(String? path);

  /// Full profile (signed-in users only).
  Future<CandidateProfile> getProfile(String candidateId);

  /// Short-lived link to a shared document in the private bucket.
  Future<String> documentUrl(String storagePath);

  /// Ids of the signed-in user's saved candidates.
  Future<Set<String>> getFavouriteIds();

  /// Saves or removes a candidate from the user's favourites.
  Future<void> setFavourite(String candidateId, {required bool saved});

  /// The signed-in user's saved candidates, most recently saved first.
  Future<List<Candidate>> getFavourites();

  /// Sends a "Request Info" enquiry and returns its reference (EQ-…).
  Future<String> sendEnquiry(CandidateEnquiry enquiry);
}

class SupabaseCandidateRepository implements CandidateRepository {
  SupabaseCandidateRepository(this._client);

  final SupabaseClient _client;

  static const _photoBucket = 'candidate-photos';

  /// Statuses listed in the directory.
  static const _listedStatuses = ['available', 'reserved'];

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(AppFailure.from(error), stackTrace);
    }
  }

  @override
  Future<List<Candidate>> getFeatured() => _guard(() async {
    final rows = await _client
        .from('candidates')
        .select(Candidate.cardColumns)
        .eq('is_featured', true)
        .inFilter('availability_status', _listedStatuses)
        .order('created_at', ascending: false)
        .order('code', ascending: true)
        .limit(10);
    return rows.map(Candidate.fromJson).toList();
  });

  @override
  Future<List<Candidate>> search(CandidateFilter filter) => _guard(() async {
    // Package and skill filters are resolved to candidate ids first
    // (a candidate must have every selected skill).
    Set<String>? ids;

    final packageId = filter.packageId;
    if (packageId != null) {
      final rows = await _client
          .from('candidate_packages')
          .select('candidate_id')
          .eq('package_id', packageId);
      ids = rows.map((r) => r['candidate_id'] as String).toSet();
    }

    for (final skill in filter.skills) {
      if (ids != null && ids.isEmpty) break;
      final rows = await _client
          .from('candidate_skills')
          .select('candidate_id')
          .eq('skill', skill.value);
      final withSkill = rows.map((r) => r['candidate_id'] as String).toSet();
      ids = ids == null ? withSkill : ids.intersection(withSkill);
    }

    if (ids != null && ids.isEmpty) return const <Candidate>[];

    var query = _client
        .from('candidates')
        .select(Candidate.cardColumns)
        .inFilter(
          'availability_status',
          filter.availableOnly ? const ['available'] : _listedStatuses,
        );

    if (ids != null) query = query.inFilter('id', ids.toList());
    if (filter.nationalities.isNotEmpty) {
      query = query.inFilter('nationality', filter.nationalities.toList());
    }
    final designation = filter.designation;
    if (designation != null) query = query.eq('designation', designation);

    // Characters with a meaning in PostgREST filters are removed.
    final term = filter.query.replaceAll(RegExp(r'[,()*%\\]'), ' ').trim();
    if (term.isNotEmpty) {
      query = query.or('display_name.ilike.%$term%,code.ilike.%$term%');
    }

    final sorted = switch (filter.sort) {
      // The code breaks ties, so the order is always the same.
      CandidateSort.newest => query
          .order('created_at', ascending: false)
          .order('code', ascending: true),
      CandidateSort.mostExperienced => query
          .order('years_experience', ascending: false)
          .order('created_at', ascending: false)
          .order('code', ascending: true),
    };
    final rows = await sorted.limit(100);
    return rows.map(Candidate.fromJson).toList();
  });

  @override
  Future<List<RecruitmentPackage>> getPackages() => _guard(() async {
    final rows = await _client
        .from('recruitment_packages')
        .select(RecruitmentPackage.columns)
        .order('sort_order', ascending: true);
    return rows.map(RecruitmentPackage.fromJson).toList();
  });

  @override
  Future<List<String>> getDesignations() => _guard(() async {
    final rows = await _client
        .from('candidates')
        .select('designation')
        .inFilter('availability_status', _listedStatuses);
    final names = rows.map((r) => r['designation'] as String).toSet().toList()
      ..sort();
    return names;
  });

  @override
  String? photoUrl(String? path) {
    if (path == null || path.isEmpty) return null;
    return _client.storage.from(_photoBucket).getPublicUrl(path);
  }

  static const _documentBucket = 'candidate-documents';

  @override
  Future<CandidateProfile> getProfile(String candidateId) => _guard(() async {
    // The six reads run in parallel.
    final Future<PostgrestMap> rowRequest = _client
        .from('candidates')
        .select(CandidateProfile.profileColumns)
        .eq('id', candidateId)
        .single();
    final Future<PostgrestList> skillsRequest = _client
        .from('candidate_skills')
        .select('skill')
        .eq('candidate_id', candidateId);
    final Future<PostgrestList> languagesRequest = _client
        .from('candidate_languages')
        .select('language, proficiency')
        .eq('candidate_id', candidateId)
        .order('language', ascending: true);
    final Future<PostgrestList> experienceRequest = _client
        .from('candidate_experience')
        .select('country, role, start_year, end_year, description')
        .eq('candidate_id', candidateId)
        .order('start_year', ascending: false);
    final Future<PostgrestList> packagesRequest = _client
        .from('candidate_packages')
        .select(
          'recruitment_packages(${RecruitmentPackage.columns}, sort_order)',
        )
        .eq('candidate_id', candidateId);
    final Future<PostgrestList> documentsRequest = _client
        .from('candidate_documents')
        .select('id, document_type, title, storage_path')
        .eq('candidate_id', candidateId)
        .order('created_at', ascending: true);

    // Future.wait passes on the first error unchanged (e.g. no internet).
    final results = await Future.wait<Object>([
      rowRequest,
      skillsRequest,
      languagesRequest,
      experienceRequest,
      packagesRequest,
      documentsRequest,
    ]);
    final row = results[0] as PostgrestMap;
    final skills = results[1] as PostgrestList;
    final languages = results[2] as PostgrestList;
    final experience = results[3] as PostgrestList;
    final packages = results[4] as PostgrestList;
    final documents = results[5] as PostgrestList;

    // Inactive packages are hidden by Row Level Security (returned as null).
    final packageRows = [
      for (final r in packages)
        if (r['recruitment_packages'] case final Map<String, dynamic> p) p,
    ]..sort(
        (a, b) => (a['sort_order'] as int).compareTo(b['sort_order'] as int),
      );

    return CandidateProfile(
      candidate: Candidate.fromJson(row),
      bio: row['bio'] as String? ?? '',
      highestQualification: row['highest_qualification'] as String?,
      religion: row['religion'] as String?,
      maritalStatus: row['marital_status'] as String?,
      skills: [
        for (final r in skills)
          ?CandidateSkill.fromValue(r['skill'] as String?),
      ],
      languages: languages.map(CandidateLanguage.fromJson).toList(),
      experience: experience.map(CandidateExperience.fromJson).toList(),
      packages: packageRows.map(RecruitmentPackage.fromJson).toList(),
      documents: documents.map(CandidateDocument.fromJson).toList(),
    );
  });

  @override
  Future<String> documentUrl(String storagePath) => _guard(
    () => _client.storage
        .from(_documentBucket)
        .createSignedUrl(storagePath, 600),
  );

  @override
  Future<Set<String>> getFavouriteIds() => _guard(() async {
    final rows = await _client
        .from('candidate_favourites')
        .select('candidate_id');
    return rows.map((r) => r['candidate_id'] as String).toSet();
  });

  @override
  Future<void> setFavourite(String candidateId, {required bool saved}) =>
      _guard(() async {
        if (!saved) {
          await _client
              .from('candidate_favourites')
              .delete()
              .eq('candidate_id', candidateId);
          return;
        }
        try {
          // user_id defaults to the signed-in user.
          await _client
              .from('candidate_favourites')
              .insert({'candidate_id': candidateId});
        } on PostgrestException catch (error) {
          // Already saved (e.g. on another device).
          if (error.code != '23505') rethrow;
        }
      });

  @override
  Future<List<Candidate>> getFavourites() => _guard(() async {
    final rows = await _client
        .from('candidate_favourites')
        .select('created_at, candidates(${Candidate.cardColumns})')
        .order('created_at', ascending: false);
    // Candidates that are no longer listed come back as null.
    return [
      for (final r in rows)
        if (r['candidates'] case final Map<String, dynamic> c)
          Candidate.fromJson(c),
    ];
  });

  @override
  Future<String> sendEnquiry(CandidateEnquiry enquiry) => _guard(() async {
    final row = await _client
        .from('candidate_enquiries')
        .insert(enquiry.toInsertJson())
        .select('reference')
        .single();
    return row['reference'] as String;
  });
}

/// Used when the app has no Supabase settings.
class UnavailableCandidateRepository implements CandidateRepository {
  const UnavailableCandidateRepository();

  static const _failure = ServerFailure(
    message: 'Candidates cannot be loaded: the app is not connected to its '
        'server.',
  );

  @override
  Future<List<Candidate>> getFeatured() => Future.error(_failure);

  @override
  Future<List<Candidate>> search(CandidateFilter filter) =>
      Future.error(_failure);

  @override
  Future<List<RecruitmentPackage>> getPackages() => Future.error(_failure);

  @override
  Future<List<String>> getDesignations() => Future.error(_failure);

  @override
  String? photoUrl(String? path) => null;

  @override
  Future<CandidateProfile> getProfile(String candidateId) =>
      Future.error(_failure);

  @override
  Future<String> documentUrl(String storagePath) => Future.error(_failure);

  @override
  Future<Set<String>> getFavouriteIds() => Future.error(_failure);

  @override
  Future<void> setFavourite(String candidateId, {required bool saved}) =>
      Future.error(_failure);

  @override
  Future<List<Candidate>> getFavourites() => Future.error(_failure);

  @override
  Future<String> sendEnquiry(CandidateEnquiry enquiry) =>
      Future.error(_failure);
}

final candidateRepositoryProvider = Provider<CandidateRepository>((ref) {
  if (!Env.isSupabaseConfigured) return const UnavailableCandidateRepository();
  return SupabaseCandidateRepository(ref.watch(supabaseClientProvider));
});

final featuredCandidatesProvider = FutureProvider<List<Candidate>>(
  (ref) => ref.watch(candidateRepositoryProvider).getFeatured(),
);

final recruitmentPackagesProvider = FutureProvider<List<RecruitmentPackage>>(
  (ref) => ref.watch(candidateRepositoryProvider).getPackages(),
);

final candidateDesignationsProvider = FutureProvider<List<String>>(
  (ref) => ref.watch(candidateRepositoryProvider).getDesignations(),
);

/// Directory results for a filter (kept only while the screen is open).
final candidateSearchProvider =
    FutureProvider.family<List<Candidate>, CandidateFilter>(
      (ref, filter) => ref.watch(candidateRepositoryProvider).search(filter),
      isAutoDispose: true,
    );

/// A candidate's full profile (signed-in users only).
final candidateProfileProvider =
    FutureProvider.family<CandidateProfile, String>(
      (ref, id) => ref.watch(candidateRepositoryProvider).getProfile(id),
      isAutoDispose: true,
    );

/// Ids of the signed-in user's saved candidates (empty for guests).
final favouriteIdsProvider =
    AsyncNotifierProvider<FavouriteIdsNotifier, Set<String>>(
      FavouriteIdsNotifier.new,
    );

class FavouriteIdsNotifier extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() async {
    final user = await ref.watch(authStateProvider.future);
    if (user == null) return const <String>{};
    return ref.watch(candidateRepositoryProvider).getFavouriteIds();
  }

  bool isSaved(String candidateId) =>
      state.value?.contains(candidateId) ?? false;

  /// Saves or removes [candidateId]. The heart changes straight away and
  /// is restored if the server refuses; the error is passed on.
  Future<void> toggle(String candidateId) async {
    final before = state.value ?? const <String>{};
    final saved = !before.contains(candidateId);
    state = AsyncData(
      saved ? {...before, candidateId} : ({...before}..remove(candidateId)),
    );
    try {
      await ref
          .read(candidateRepositoryProvider)
          .setFavourite(candidateId, saved: saved);
      if (!ref.mounted) return;
      ref.invalidate(savedMaidsProvider);
    } catch (_) {
      if (ref.mounted) state = AsyncData(before);
      rethrow;
    }
  }
}

/// The signed-in user's saved candidates (Saved Maids page).
final savedMaidsProvider = FutureProvider<List<Candidate>>(
  (ref) async {
    final user = await ref.watch(authStateProvider.future);
    if (user == null) return const <Candidate>[];
    return ref.watch(candidateRepositoryProvider).getFavourites();
  },
  isAutoDispose: true,
);
