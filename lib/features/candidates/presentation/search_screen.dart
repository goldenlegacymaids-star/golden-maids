import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_search_bar.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../data/candidate_repository.dart';
import '../domain/candidate.dart';
import 'open_candidate.dart';
import 'widgets/candidate_cards.dart';

/// Maids matching a search: by nationality when the words start a
/// nationality's name ("ken" → Kenya), otherwise by name or code (GM-…).
final maidSearchProvider = FutureProvider.family<List<Candidate>, String>((
  ref,
  query,
) async {
  final term = query.trim().toLowerCase();
  var nationalities = const <MaidNationality>[];
  try {
    nationalities = await ref.watch(maidNationalitiesProvider.future);
  } on Object {
    // Without the list, search by name and code only.
  }
  final matching = {
    for (final n in nationalities)
      if (n.name.toLowerCase().startsWith(term)) n.name,
  };
  final repository = ref.watch(candidateRepositoryProvider);
  return repository.search(
    matching.isEmpty
        ? CandidateFilter(query: query.trim())
        : CandidateFilter(nationalities: matching),
  );
}, isAutoDispose: true);

/// Search maids by name, code (GM-…) or nationality.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  static const int minQueryLength = 2;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    // Wait until the user pauses typing, to avoid a request per keystroke.
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    return PageScaffold(
      title: 'Search',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding,
            ),
            child: AppSearchBar(
              controller: _controller,
              autofocus: true,
              onChanged: _onChanged,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final listPadding = EdgeInsets.fromLTRB(
      AppSpacing.screenPadding,
      AppSpacing.xs,
      AppSpacing.screenPadding,
      bottomInset + AppSpacing.xl,
    );

    if (_query.length < SearchScreen.minQueryLength) {
      return ListView(
        padding: listPadding,
        children: [
          Text(
            'Type a name, a code (GM-…) or a nationality, such as Kenya or '
            'Philippines.',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: () => unawaited(context.push(AppRoutes.maids)),
              child: const Text('See all maids'),
            ),
          ),
        ],
      );
    }

    final maids = ref.watch(maidSearchProvider(_query));
    final candidates = ref.watch(candidateRepositoryProvider);

    if (maids.isLoading && !maids.hasValue) {
      return const Center(child: CircularProgressIndicator());
    }
    if (maids.hasError && !maids.hasValue) {
      return ErrorState(
        failure: AppFailure.from(maids.error!),
        onRetry: () => ref.invalidate(maidSearchProvider(_query)),
      );
    }

    final maidList = maids.value ?? const <Candidate>[];
    if (maidList.isEmpty) {
      return const SingleChildScrollView(
        child: EmptyState(
          icon: Icons.search_off_rounded,
          title: 'No results',
          message: 'Try a name, a code (GM-…) or a nationality.',
        ),
      );
    }

    return ListView(
      padding: listPadding,
      children: [
        Text(
          'Maids · ${maidList.length}',
          style: AppTypography.titleSmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        for (final candidate in maidList) ...[
          CandidateListTile(
            candidate: candidate,
            photoUrl: candidates.photoUrl(candidate.photoPath),
            onTap: () => openCandidate(context, ref, candidate),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ],
    );
  }
}
