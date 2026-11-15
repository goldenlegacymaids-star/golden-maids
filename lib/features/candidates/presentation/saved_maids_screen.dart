import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/routing/app_routes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/page_scaffold.dart';
import '../data/candidate_repository.dart';
import 'open_candidate.dart';
import 'widgets/candidate_cards.dart';

/// The signed-in user's saved candidates (Profile → Saved Maids).
class SavedMaidsScreen extends ConsumerWidget {
  const SavedMaidsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(savedMaidsProvider);
    // Hearts removed on this page hide the candidate straight away.
    final savedIds = ref.watch(favouriteIdsProvider).value;
    final repository = ref.watch(candidateRepositoryProvider);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return PageScaffold(
      title: 'Saved Maids',
      body: saved.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => SingleChildScrollView(
          child: ErrorState(
            failure: AppFailure.from(error),
            onRetry: () => ref.invalidate(savedMaidsProvider),
          ),
        ),
        data: (all) {
          final candidates = savedIds == null
              ? all
              : all.where((c) => savedIds.contains(c.id)).toList();
          if (candidates.isEmpty) {
            return SingleChildScrollView(
              child: EmptyState(
                icon: Icons.favorite_border_rounded,
                title: 'No saved maids yet',
                message:
                    'Tap the heart on a candidate to save her here and '
                    'compare later.',
                actionLabel: 'Find a Maid',
                onAction: () => context.go(AppRoutes.maids),
              ),
            );
          }
          return ListView.separated(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.screenPadding,
              AppSpacing.xs,
              AppSpacing.screenPadding,
              bottomInset + AppSpacing.xl,
            ),
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
          );
        },
      ),
    );
  }
}
