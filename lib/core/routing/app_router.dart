import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/authentication/data/auth_providers.dart';
import '../../features/authentication/domain/auth_repository.dart';
import '../../features/authentication/presentation/forgot_password_screen.dart';
import '../../features/authentication/presentation/new_password_screen.dart';
import '../../features/authentication/presentation/sign_in_screen.dart';
import '../../features/authentication/presentation/sign_up_screen.dart';
import '../../features/authentication/presentation/verify_code_args.dart';
import '../../features/authentication/presentation/verify_code_screen.dart';
import '../../features/authentication/presentation/welcome_screen.dart';
import '../../features/bookings/presentation/bookings_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/onboarding/presentation/splash_screen.dart';
import '../../features/profile/presentation/edit_profile_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/wallet/presentation/wallet_screen.dart';
import '../config/env.dart';
import 'app_routes.dart';
import 'app_shell.dart';
import 'design_preview_screen.dart';

/// Tells GoRouter to re-run its redirect when the session changes.
class _RouterRefresh extends ChangeNotifier {
  void notify() => notifyListeners();
}

/// Pages that require a signed-in user.
const Set<String> _signedInOnly = {AppRoutes.newPassword, AppRoutes.editProfile};

/// Session-aware redirects:
/// - signed-in users never see the welcome / sign-in / sign-up screens;
/// - account pages (e.g. edit profile, new password) require a session;
/// - the verification screen needs its arguments (lost on a web refresh).
///
/// The main tabs stay open to guests (guest browsing); tabs with private
/// data show a sign-in prompt instead.
String? _redirect(AuthRepository auth, GoRouterState state) {
  final location = state.matchedLocation;
  final signedIn = auth.currentUser != null;

  if (signedIn && AppRoutes.guestOnly.contains(location)) {
    return AppRoutes.home;
  }
  if (!signedIn && _signedInOnly.contains(location)) {
    return AppRoutes.signIn;
  }
  if (location == AppRoutes.verifyCode && state.extra is! VerifyCodeArgs) {
    return signedIn ? AppRoutes.home : AppRoutes.signIn;
  }
  return null;
}

/// The app's single [GoRouter] instance.
final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authRepositoryProvider);
  final refresh = _RouterRefresh();
  // Navigator for full-screen pages shown above the bottom navigation.
  final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
  final subscription = auth.authStateChanges().listen((_) => refresh.notify());

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: !Env.isProduction,
    refreshListenable: refresh,
    redirect: (context, state) => _redirect(auth, state),
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        name: 'splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        name: 'onboarding',
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.welcome,
        name: 'welcome',
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.signIn,
        name: 'sign-in',
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: AppRoutes.signUp,
        name: 'sign-up',
        builder: (context, state) => const SignUpScreen(),
      ),
      GoRoute(
        path: AppRoutes.verifyCode,
        name: 'verify-code',
        builder: (context, state) =>
            VerifyCodeScreen(args: state.extra as VerifyCodeArgs),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        name: 'forgot-password',
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: AppRoutes.newPassword,
        name: 'new-password',
        builder: (context, state) => const NewPasswordScreen(),
      ),
      // Main tabs. Each branch keeps its own navigation stack and state.
      StatefulShellRoute(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        navigatorContainerBuilder: (context, navigationShell, children) =>
            FadingTabContainer(
              currentIndex: navigationShell.currentIndex,
              children: children,
            ),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.home,
                name: 'home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.bookings,
                name: 'bookings',
                builder: (context, state) => const BookingsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.wallet,
                name: 'wallet',
                builder: (context, state) => const WalletScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.profile,
                name: 'profile',
                builder: (context, state) => const ProfileScreen(),
                routes: [
                  GoRoute(
                    path: 'edit',
                    name: 'edit-profile',
                    // Full screen, above the bottom navigation.
                    parentNavigatorKey: rootNavigatorKey,
                    builder: (context, state) => const EditProfileScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      if (!Env.isProduction)
        GoRoute(
          path: AppRoutes.designPreview,
          name: 'design-preview',
          builder: (context, state) => const DesignPreviewScreen(),
        ),
    ],
  );

  ref.onDispose(() {
    unawaited(subscription.cancel());
    router.dispose();
    refresh.dispose();
  });
  return router;
});
