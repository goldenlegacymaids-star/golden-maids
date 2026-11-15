import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/routing/app_routes.dart';
import '../../authentication/data/auth_providers.dart';
import '../../authentication/presentation/widgets/sign_in_prompt.dart';
import '../domain/candidate.dart';

/// Whether someone is signed in right now.
bool isSignedIn(WidgetRef ref) =>
    (ref.read(authStateProvider).value ??
        ref.read(authRepositoryProvider).currentUser) !=
    null;

/// Asks a guest to sign in, in a bottom sheet above the navigation bar.
void showSignInSheet(
  BuildContext context, {
  required String title,
  String message =
      'Create a free account or sign in to see full profiles, save '
      'favourites and send hiring requests.',
}) {
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
            title: title,
            message: message,
            onBeforeNavigate: () => Navigator.of(sheetContext).pop(),
          ),
        ),
      ),
    ),
  );
}

/// Opens a candidate from a card: the full profile for signed-in users,
/// a sign-in prompt for guests.
void openCandidate(BuildContext context, WidgetRef ref, Candidate candidate) {
  if (!isSignedIn(ref)) {
    showSignInSheet(context, title: 'Sign in to view ${candidate.title}');
    return;
  }
  unawaited(context.push(AppRoutes.candidate(candidate.id)));
}
