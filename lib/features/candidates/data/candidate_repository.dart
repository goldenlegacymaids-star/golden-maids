import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/env.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/services/supabase_providers.dart';
import '../domain/candidate.dart';

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
