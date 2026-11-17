import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
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

  /// The filter chips (for tests).
  static const locationChipKey = Key('filter-location');
  static const visaChipKey = Key('filter-visa');
  static const nationalityChipKey = Key('filter-nationality');

  /// The filter bar that slides away while scrolling (for tests).
  static const filterBarKey = Key('filter-bar');

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

  /// Filters slide away while scrolling down and come back on scrolling up.
  bool _filtersVisible = true;

  void _showFilters(bool visible) {
    if (visible != _filtersVisible) setState(() => _filtersVisible = visible);
  }

  bool _onResultsScroll(ScrollNotification notification) {
    if (notification.depth != 0 ||
        notification.metrics.axis != Axis.vertical ||
        notification is! ScrollUpdateNotification) {
      return false;
    }
    final delta = notification.scrollDelta ?? 0;
    if (notification.metrics.pixels <= 0) {
      _showFilters(true);
    } else if (delta > 4) {
      _showFilters(false);
    } else if (delta < -4) {
      _showFilters(true);
    }
    return false;
  }

  Future<void> _pickLocation() async {
    final picked = await _pickOne<MaidLocation>(
      context,
      title: 'Where is she?',
      selected: _filter.location,
      options: [
        (null, 'Any location'),
        for (final location in MaidLocation.values) (location, location.label),
      ],
    );
    if (picked != null && mounted) {
      setState(() => _filter = _filter.copyWith(location: () => picked.$1));
    }
  }

  Future<void> _pickVisa() async {
    final picked = await _pickOne<VisaRoute>(
      context,
      title: 'Visa',
      selected: _filter.visa,
      options: [
        (null, 'Any visa'),
        for (final visa in VisaRoute.values) (visa, visa.label),
      ],
    );
    if (picked != null && mounted) {
      setState(() => _filter = _filter.copyWith(visa: () => picked.$1));
    }
  }

  Future<void> _pickNationalities(List<MaidNationality> nationalities) async {
    final picked = await showModalBottomSheet<Set<String>>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (context) => _NationalitySheet(
        nationalities: nationalities,
        initial: _filter.nationalities,
      ),
    );
    if (picked != null && mounted) {
      setState(() => _filter = _filter.copyWith(nationalities: picked));
    }
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
            ),
          ),
          // One row of filters + the count and sort. Slides away while
          // scrolling down so the maids get the screen.
          ClipRect(
            child: AnimatedAlign(
              key: CandidateDirectoryScreen.filterBarKey,
              alignment: Alignment.topCenter,
              heightFactor: _filtersVisible ? 1 : 0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: IgnorePointer(
                ignoring: !_filtersVisible,
                child: ExcludeSemantics(
                  excluding: !_filtersVisible,
                  child: _filterBar(nationalities, sheetFilters),
                ),
              ),
            ),
          ),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: _onResultsScroll,
              child: _Results(filter: _filter),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filterBar(List<MaidNationality> nationalities, int sheetFilters) {
    final chosen = _filter.nationalities;
    final nationalityLabel = switch (chosen.length) {
      0 => 'Nationality',
      1 => chosen.first,
      _ => '${chosen.first} +${chosen.length - 1}',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 38,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.screenPadding,
            ),
            children: [
              // First, so it is never off screen: job type, package, skills
              // and availability. Shows how many are set.
              Tooltip(
                message: 'Filters',
                child: _DropdownChip(
                  label: sheetFilters > 0 ? '$sheetFilters' : '',
                  active: sheetFilters > 0,
                  icon: Icons.tune_rounded,
                  showArrow: false,
                  onTap: () => unawaited(_openFilters()),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _DropdownChip(
                key: CandidateDirectoryScreen.locationChipKey,
                label: _filter.location?.label ?? 'Location',
                active: _filter.location != null,
                onTap: () => unawaited(_pickLocation()),
              ),
              const SizedBox(width: AppSpacing.xs),
              _DropdownChip(
                key: CandidateDirectoryScreen.visaChipKey,
                label: _filter.visa?.label ?? 'Visa',
                active: _filter.visa != null,
                onTap: () => unawaited(_pickVisa()),
              ),
              const SizedBox(width: AppSpacing.xs),
              _DropdownChip(
                key: CandidateDirectoryScreen.nationalityChipKey,
                label: nationalityLabel,
                active: chosen.isNotEmpty,
                leading: chosen.length == 1
                    ? _flagFor(nationalities, chosen.first)
                    : null,
                onTap: () => unawaited(_pickNationalities(nationalities)),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenPadding,
            AppSpacing.xxs,
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
      ],
    );
  }
}

Widget? _flagFor(List<MaidNationality> nationalities, String name) {
  for (final nationality in nationalities) {
    if (nationality.name == name) {
      return FlagImage(code: nationality.code, height: 12);
    }
  }
  return null;
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

/// A filter chip that opens a sheet: blue when set, with a down arrow.
class _DropdownChip extends StatelessWidget {
  const _DropdownChip({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    this.leading,
    this.icon,
    this.showArrow = true,
  });

  /// Empty for an icon-only chip.
  final String label;
  final bool active;
  final VoidCallback onTap;
  final Widget? leading;
  final IconData? icon;
  final bool showArrow;

  @override
  Widget build(BuildContext context) {
    final foreground = active ? AppColors.infoText : AppColors.textPrimary;
    final chipIcon = icon;
    final chipLeading = leading;
    return Semantics(
      button: true,
      selected: active,
      child: Material(
        color: active ? AppColors.lightBlue : AppColors.white,
        shape: StadiumBorder(
          side: BorderSide(
            color: active
                ? AppColors.primary.withValues(alpha: 0.45)
                : AppColors.border,
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.sm,
              right: AppSpacing.xs,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (chipIcon != null) ...[
                  Icon(chipIcon, size: 18, color: foreground),
                  if (label.isNotEmpty) const SizedBox(width: AppSpacing.xxs),
                ],
                if (chipLeading != null) ...[
                  chipLeading,
                  const SizedBox(width: AppSpacing.xxs),
                ],
                if (label.isNotEmpty)
                  Text(
                    label,
                    style: AppTypography.labelMedium.copyWith(
                      color: foreground,
                    ),
                  ),
                if (showArrow)
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: foreground,
                  )
                else
                  const SizedBox(width: AppSpacing.xxs),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A one-choice sheet. Returns the choice in a record, so that "Any"
/// (null) can be told apart from closing the sheet.
Future<(T?,)?> _pickOne<T>(
  BuildContext context, {
  required String title,
  required T? selected,
  required List<(T?, String)> options,
}) {
  return showModalBottomSheet<(T?,)>(
    context: context,
    useRootNavigator: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                AppSpacing.xs,
              ),
              child: Text(title, style: AppTypography.titleLarge),
            ),
            for (final (value, label) in options)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                ),
                title: Text(label, style: AppTypography.bodyMedium),
                trailing: value == selected
                    ? const Icon(
                        Icons.check_rounded,
                        color: AppColors.primary,
                      )
                    : null,
                selected: value == selected,
                onTap: () => Navigator.of(context).pop((value,)),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Tick one or more nationalities (flags), then "Show results".
class _NationalitySheet extends StatefulWidget {
  const _NationalitySheet({
    required this.nationalities,
    required this.initial,
  });

  final List<MaidNationality> nationalities;
  final Set<String> initial;

  @override
  State<_NationalitySheet> createState() => _NationalitySheetState();
}

class _NationalitySheetState extends State<_NationalitySheet> {
  late Set<String> _draft = {...widget.initial};

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.xl,
                0,
                AppSpacing.xl,
                AppSpacing.xs,
              ),
              child: Text('Nationality', style: AppTypography.titleLarge),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl,
                    ),
                    title: const Text(
                      'All nationalities',
                      style: AppTypography.bodyMedium,
                    ),
                    trailing: _draft.isEmpty
                        ? const Icon(
                            Icons.check_rounded,
                            color: AppColors.primary,
                          )
                        : null,
                    onTap: () => setState(() => _draft = {}),
                  ),
                  for (final nationality in widget.nationalities)
                    CheckboxListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xl,
                      ),
                      secondary: FlagImage(code: nationality.code, height: 16),
                      title: Text(
                        nationality.name,
                        style: AppTypography.bodyMedium,
                      ),
                      value: _draft.contains(nationality.name),
                      onChanged: (on) => setState(() {
                        _draft = {..._draft};
                        if (on ?? false) {
                          _draft.add(nationality.name);
                        } else {
                          _draft.remove(nationality.name);
                        }
                      }),
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
              child: AppButton(
                label: 'Show results',
                onPressed: () => Navigator.of(context).pop(_draft),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
