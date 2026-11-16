import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_chip.dart';
import '../../../core/widgets/app_search_bar.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../candidates/data/candidate_repository.dart';
import '../../candidates/domain/candidate.dart';
import '../../candidates/presentation/open_candidate.dart';
import '../../candidates/presentation/widgets/candidate_cards.dart';
import '../data/catalog_repository.dart';
import '../domain/catalog.dart';
import 'catalog_display.dart';
import 'widgets/service_tiles.dart';

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

/// Search maids (name, code or nationality) and home services (name or
/// description, optionally within a category).
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  static const int minQueryLength = 2;

  /// Maids shown before "See all maids".
  static const int maidPreview = 5;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  String _query = '';
  String? _categoryId;

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

  Future<void> _pickCategory(List<ServiceCategory> categories) async {
    const allKey = '__all__';
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  0,
                  AppSpacing.xl,
                  AppSpacing.xs,
                ),
                child: Text(
                  'Filter by category',
                  style: AppTypography.titleMedium,
                ),
              ),
              ListTile(
                title: const Text('All categories'),
                selected: _categoryId == null,
                onTap: () => Navigator.of(context).pop(allKey),
              ),
              for (final category in categories)
                ListTile(
                  leading: Icon(categoryIcon(category.icon)),
                  title: Text(category.name),
                  selected: _categoryId == category.id,
                  onTap: () => Navigator.of(context).pop(category.id),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => _categoryId = selected == allKey ? null : selected);
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider).value ?? const [];
    final selectedCategory = categories
        .where((c) => c.id == _categoryId)
        .firstOrNull;

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
              hint: 'Search maids, nationalities or services...',
              onChanged: _onChanged,
              onFilterPressed: categories.isEmpty
                  ? null
                  : () => unawaited(_pickCategory(categories)),
            ),
          ),
          if (selectedCategory != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.screenPadding,
                AppSpacing.sm,
                AppSpacing.screenPadding,
                0,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: AppChip(
                  label: '${selectedCategory.name}  ✕',
                  selected: true,
                  onTap: () => setState(() => _categoryId = null),
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(child: _buildBody(categories)),
        ],
      ),
    );
  }

  Widget _buildBody(List<ServiceCategory> categories) {
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
          const Text('Browse categories', style: AppTypography.titleSmall),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final category in categories)
                AppChip(
                  label: category.name,
                  icon: categoryIcon(category.icon),
                  selected: false,
                  onTap: () => unawaited(
                    context.push(AppRoutes.category(category.slug)),
                  ),
                ),
            ],
          ),
        ],
      );
    }

    final results = ref.watch(serviceSearchProvider(_query));
    final catalog = ref.watch(catalogRepositoryProvider);
    // A service category filter is about services: maids are left out.
    final maids = _categoryId == null
        ? ref.watch(maidSearchProvider(_query))
        : const AsyncData(<Candidate>[]);
    final candidates = ref.watch(candidateRepositoryProvider);

    if (results.isLoading && maids.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (results.hasError && !results.hasValue) {
      return ErrorState(
        failure: AppFailure.from(results.error!),
        onRetry: () {
          ref
            ..invalidate(serviceSearchProvider(_query))
            ..invalidate(maidSearchProvider(_query));
        },
      );
    }

    final services = results.value ?? const <HomeService>[];
    final filtered = _categoryId == null
        ? services
        : services.where((s) => s.categoryId == _categoryId).toList();
    // A maid search that fails only hides the maids section.
    final maidList = maids.value ?? const <Candidate>[];
    if (filtered.isEmpty && maidList.isEmpty && !maids.isLoading) {
      return const SingleChildScrollView(
        child: EmptyState(
          icon: Icons.search_off_rounded,
          title: 'No results',
          message:
              'Try a name, a code (GM-…), a nationality or a service, or '
              'browse the categories.',
        ),
      );
    }

    final shownMaids = maidList.take(SearchScreen.maidPreview).toList();
    return ListView(
      padding: listPadding,
      children: [
        if (maidList.isNotEmpty) ...[
          Text(
            'Maids · ${maidList.length}',
            style: AppTypography.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final candidate in shownMaids) ...[
            CandidateListTile(
              candidate: candidate,
              photoUrl: candidates.photoUrl(candidate.photoPath),
              onTap: () => openCandidate(context, ref, candidate),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (maidList.length > shownMaids.length)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () => unawaited(context.push(AppRoutes.maids)),
                child: const Text('See all maids'),
              ),
            ),
          const SizedBox(height: AppSpacing.md),
        ],
        if (filtered.isNotEmpty) ...[
          if (maidList.isNotEmpty) ...[
            const Text('Services', style: AppTypography.titleSmall),
            const SizedBox(height: AppSpacing.xxs),
          ],
          Text(
            '${filtered.length} '
            '${filtered.length == 1 ? 'result' : 'results'}',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final service in filtered) ...[
            ServiceListTile(
              service: service,
              imageUrl: catalog.imageUrl(service.imagePath),
              icon: categoryIcon(
                categories
                        .where((c) => c.id == service.categoryId)
                        .firstOrNull
                        ?.icon ??
                    '',
              ),
              onTap: () =>
                  unawaited(context.push(AppRoutes.service(service.slug))),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ],
    );
  }
}
