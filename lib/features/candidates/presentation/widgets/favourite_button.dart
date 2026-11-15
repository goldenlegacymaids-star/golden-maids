import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_snackbar.dart';
import '../../data/candidate_repository.dart';
import '../open_candidate.dart';

/// Heart button that saves a candidate to the user's favourites.
/// Guests are asked to sign in.
class FavouriteButton extends ConsumerWidget {
  const FavouriteButton({
    super.key,
    required this.candidateId,
    required this.candidateTitle,
    this.size = 40,
  });

  final String candidateId;

  /// Name or code, for the screen-reader label.
  final String candidateTitle;
  final double size;

  Future<void> _toggle(BuildContext context, WidgetRef ref) async {
    if (!isSignedIn(ref)) {
      showSignInSheet(context, title: 'Sign in to save maids');
      return;
    }
    try {
      await ref.read(favouriteIdsProvider.notifier).toggle(candidateId);
    } on Object catch (error) {
      if (context.mounted) showErrorSnackBar(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved =
        ref.watch(favouriteIdsProvider).value?.contains(candidateId) ?? false;

    return Semantics(
      button: true,
      toggled: saved,
      label: saved
          ? 'Remove $candidateTitle from saved maids'
          : 'Save $candidateTitle',
      excludeSemantics: true,
      child: Tooltip(
        message: saved ? 'Remove from saved' : 'Save',
        child: Material(
          color: AppColors.white,
          shape: const CircleBorder(),
          elevation: 2,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => unawaited(_toggle(context, ref)),
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(
                saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                size: size * 0.5,
                color: saved ? AppColors.error : AppColors.textSecondary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
