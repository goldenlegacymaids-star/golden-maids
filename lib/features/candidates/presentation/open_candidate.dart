import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_snackbar.dart';
import '../../authentication/data/auth_providers.dart';
import '../../authentication/presentation/widgets/sign_in_prompt.dart';
import '../domain/candidate.dart';

/// Opens a candidate from a card.
///
/// Guests see a sign-in prompt: full profiles are for signed-in users only.
/// (The full profile screen is added in Step 2.3.)
void openCandidate(BuildContext context, WidgetRef ref, Candidate candidate) {
  final signedIn =
      (ref.read(authStateProvider).value ??
          ref.read(authRepositoryProvider).currentUser) !=
      null;

  if (!signedIn) {
    unawaited(
      showModalBottomSheet<void>(
        context: context,
        // Above the bottom navigation, so the buttons are never covered.
        useRootNavigator: true,
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(
          child: SingleChildScrollView(
            child: SignInPrompt(
              icon: Icons.person_search_rounded,
              title: 'Sign in to view ${candidate.title}',
              message:
                  'Create a free account or sign in to see full profiles, '
                  'save favourites and send hiring requests.',
              onBeforeNavigate: () => Navigator.of(sheetContext).pop(),
            ),
          ),
        ),
      ),
    );
    return;
  }

  showAppSnackBar(context, 'Full candidate profiles are coming soon.');
}
