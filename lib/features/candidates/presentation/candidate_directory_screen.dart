import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_chip.dart';
import '../../../core/widgets/app_search_bar.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../../../core/widgets/skeleton.dart';
import '../data/candidate_repository.dart';
import '../domain/candidate.dart';
import 'open_candidate.dart';
import 'widgets/candidate_cards.dart';
import 'widgets/nationality_flag.dart';

/// "Find a Maid": search and filter domestic-worker candidates.
///
/// Guests can browse the cards; opening a full profile needs an account.
class CandidateDirectoryScreen extends ConsumerStatefulWidget {
  const CandidateDirectoryScreen({
    super.key,
    this.initialVisa,
    this.initialLocation,
  });

  /// The row of nationality chips (for tests).
  static const nationalityRowKey = Key('nationality-chips');

  /// Opened from Home's "Hire a Maid" cards: that visa route is selected.
  final VisaRoute? initialVisa;
  final MaidLocation? initialLocation;

  @override
  ConsumerState<CandidateDirectoryScreen> createState() =>
      _CandidateDirectoryScreenState();
}

class _CandidateDirectoryScreenState
    extends ConsumerState<CandidateDirectoryScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  late CandidateFilter _filter = CandidateFilter(
    visa: widget.initialVisa,
    location: widget.initialLocation,
  );

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    // Wait until the user pauses typing, to avoid a request per keystroke.
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      setState(() => _filter = _filter.copyWith(query: value.trim()));
    });
  }

  void _toggleNationality(String nationality) {
    final selected = {..._filter.nationalities};
    if (!selected.remove(nationality)) selected.add(nationality);
    setState(() => _filter = _filter.copyWith(nationalities: selected));
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<CandidateFilter>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (context) => _FilterSheet(initial: _filter),
    );
    if (result != null && mounted) setState(() => _filter = result);
  }

  @override
  Widget build(BuildContext context) {
    final sheetFilters = _filter.activeCount - _filter.nationalities.length;
    final nationalities =
        ref.watch(maidNationalitiesProvider).value ?? const <MaidNationality>[];

    return PageScaffold(
      title: 'Find a Maid',
      trailing: TextButton.icon(
        onPressed: () {
          if (!isSignedIn(ref)) {
            showSignInSheet(context, title: 'Sign in to hire a maid');
            return;
          }
          unawaited(context.push(AppRoutes.hire()));
        },
        icon: const Icon(Icons.assignment_ind_rounded),
        label: const Text('Hire a Maid'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding,
            ),
            child: AppSearchBar(
              controller: _controller,
              hint: 'Search by name or code (GM-...)',
              onChanged: _onSearchChanged,
              onFilterPressed: () => unawaited(_openFilters()),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenPadding,
              ),
              children: [
                AppChip(
                  label: 'Any visa',
                  selected: _filter.visa == null,
                  onTap: () => setState(
                    () => _filter = _filter.copyWith(visa: () => null),
                  ),
                ),
                for (final visa in VisaRoute.values) ...[
                  const SizedBox(width: AppSpacing.xs),
                  AppChip(
                    label: visa.label,
                    selected: _filter.visa == visa,
                    onTap: () => setState(
                      () => _filter = _filter.copyWith(visa: () => visa),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding,
            ),
            child: LocationSwitch(
              value: _filter.location,
              onChanged: (location) => setState(
                () => _filter = _filter.copyWith(location: () => location),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            key: CandidateDirectoryScreen.nationalityRowKey,
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenPadding,
              ),
              children: [
                AppChip(
                  label: 'All',
                  selected: _filter.nationalities.isEmpty,
                  onTap: () => setState(
                    () => _filter = _filter.copyWith(nationalities: const {}),
                  ),
                ),
                for (final nationality in nationalities) ...[
                  const SizedBox(width: AppSpacing.xs),
                  AppChip(
                    label: nationality.name,
                    leading: FlagImage(code: nationality.code, height: 14),
                    selected: _filter.nationalities.contains(nationality.name),
                    onTap: () => _toggleNationality(nationality.name),
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              AppSpacing.xs,
              AppSpacing.sm,
              0,
            ),
            child: Row(
              children: [
                Expanded(child: _ResultCount(filter: _filter)),
                if (sheetFilters > 0)
                  TextButton(
                    onPressed: () =>
                        setState(() => _filter = _filter.cleared().copyWith(
                          nationalities: _filter.nationalities,
                        )),
                    child: Text('Clear filters ($sheetFilters)'),
                  ),
                PopupMenuButton<CandidateSort>(
                  tooltip: 'Sort',
                  initialValue: _filter.sort,
                  onSelected: (sort) =>
                      setState(() => _filter = _filter.copyWith(sort: sort)),
                  itemBuilder: (context) => [
                    for (final sort in CandidateSort.values)
                      PopupMenuItem(value: sort, child: Text(sort.label)),
                  ],
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.sort_rounded,
                          size: 18,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: AppSpacing.xxs),
                        Text(
                          _filter.sort.label,
                          style: AppTypography.labelMedium.copyWith(
                            color: AppColors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _Results(filter: _filter)),
        ],
      ),
    );
  }
}

class _ResultCount extends ConsumerWidget {
  const _ResultCount({required this.filter});

  final CandidateFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(candidateSearchProvider(filter)).value?.length;
    return Text(
      count == null
          ? ''
          : '$count ${count == 1 ? 'candidate' : 'candidates'}',
      style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.filter});

  final CandidateFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(candidateSearchProvider(filter));
    final repository = ref.watch(candidateRepositoryProvider);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final listPadding = EdgeInsets.fromLTRB(
      AppSpacing.screenPadding,
      AppSpacing.xs,
      AppSpacing.screenPadding,
      bottomInset + AppSpacing.xl,
    );

    return results.when(
      loading: () => ListView.separated(
        padding: listPadding,
        itemCount: 4,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
        itemBuilder: (_, _) => const Skeleton(
          child: SkeletonBox(height: 128, borderRadius: AppRadius.lgAll),
        ),
      ),
      error: (error, _) => SingleChildScrollView(
        child: ErrorState(
          failure: AppFailure.from(error),
          onRetry: () => ref.invalidate(candidateSearchProvider(filter)),
        ),
      ),
      data: (candidates) {
        if (candidates.isEmpty) {
          return const SingleChildScrollView(
            child: EmptyState(
              icon: Icons.person_search_rounded,
              title: 'No candidates found',
              message:
                  'Try fewer filters or another nationality. New candidates '
                  'are added regularly.',
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(candidateSearchProvider(filter));
            try {
              await ref.read(candidateSearchProvider(filter).future);
            } on Object {
              // The error is shown in place of the list.
            }
          },
          child: ListView.separated(
            padding: listPadding,
            itemCount: candidates.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final candidate = candidates[index];
              return CandidateListTile(
                candidate: candidate,
                photoUrl: repository.photoUrl(candidate.photoPath),
                onTap: () => openCandidate(context, ref, candidate),
              );
            },
          ),
        );
      },
    );
  }
}

/// Bottom sheet with the job type, package, skill and availability filters.
class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet({required this.initial});

  final CandidateFilter initial;

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late CandidateFilter _draft = widget.initial;

  @override
  Widget build(BuildContext context) {
    final designations =
        ref.watch(candidateDesignationsProvider).value ?? const <String>[];
    final packages = ref.watch(recruitmentPackagesProvider).value ??
        const <RecruitmentPackage>[];

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  0,
                  AppSpacing.xl,
                  AppSpacing.md,
                ),
                children: [
                  const Text('Filters', style: AppTypography.titleLarge),
                  if (designations.isNotEmpty) ...[
                    const _SheetHeading('Job type'),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        for (final designation in designations)
                          AppChip(
                            label: designation,
                            selected: _draft.designation == designation,
                            onTap: () => setState(
                              () => _draft = _draft.copyWith(
                                designation: () =>
                                    _draft.designation == designation
                                    ? null
                                    : designation,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                  if (packages.isNotEmpty) ...[
                    const _SheetHeading('Package'),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: [
                        for (final package in packages)
                          AppChip(
                            label: package.shortName,
                            selected: _draft.packageId == package.id,
                            onTap: () => setState(
                              () => _draft = _draft.copyWith(
                                packageId: () => _draft.packageId == package.id
                                    ? null
                                    : package.id,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                  const _SheetHeading('Skills'),
                  Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: AppSpacing.xs,
                    children: [
                      for (final skill in CandidateSkill.values)
                        AppChip(
                          label: skill.label,
                          selected: _draft.skills.contains(skill),
                          onTap: () {
                            final skills = {..._draft.skills};
                            if (!skills.remove(skill)) skills.add(skill);
                            setState(
                              () => _draft = _draft.copyWith(skills: skills),
                            );
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Available now only',
                      style: AppTypography.titleSmall,
                    ),
                    subtitle: const Text(
                      'Hide candidates who are reserved',
                      style: AppTypography.bodySmall,
                    ),
                    value: _draft.availableOnly,
                    onChanged: (value) => setState(
                      () => _draft = _draft.copyWith(availableOnly: value),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.xs,
                AppSpacing.xl,
                AppSpacing.md,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: AppButton(
                      label: 'Reset',
                      variant: AppButtonVariant.outline,
                      onPressed: () => setState(
                        () => _draft = _draft.cleared().copyWith(
                          nationalities: _draft.nationalities,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: AppButton(
                      label: 'Show results',
                      onPressed: () => Navigator.of(context).pop(_draft),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetHeading extends StatelessWidget {
  const _SheetHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(
        top: AppSpacing.lg,
        bottom: AppSpacing.xs,
      ),
      child: Text(text, style: AppTypography.titleSmall),
    );
  }
}

/// "All · In the UAE · Outside the UAE" switch above the maid list.
class LocationSwitch extends StatelessWidget {
  const LocationSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  /// Null = all maids.
  final MaidLocation? value;
  final ValueChanged<MaidLocation?> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = <(MaidLocation?, String)>[
      (null, 'All'),
      for (final location in MaidLocation.values) (location, location.label),
    ];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppColors.white.withValues(alpha: 0.6),
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          for (final (location, label) in options)
            Expanded(
              child: Semantics(
                button: true,
                selected: value == location,
                child: InkWell(
                  borderRadius: AppRadius.smAll,
                  onTap: () => onChanged(location),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    constraints: const BoxConstraints(minHeight: 40),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xxs,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: value == location ? AppColors.white : null,
                      borderRadius: AppRadius.smAll,
                      boxShadow: value == location ? AppShadows.soft : null,
                    ),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: value == location
                          ? AppTypography.labelMedium.copyWith(
                              color: AppColors.infoText,
                            )
                          : AppTypography.bodySmall,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
