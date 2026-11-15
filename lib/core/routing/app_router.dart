import 'dart:async';

import 'package:flutter/foundation.dart';
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
import '../../features/home/presentation/temporary_home_screen.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/onboarding/presentation/splash_screen.dart';
import '../config/env.dart';
import 'app_routes.dart';
import 'design_preview_screen.dart';

/// Tells GoRouter to re-run its redirect when the session changes.
class _RouterRefresh extends ChangeNotifier {
  void notify() => notifyListeners();
}

/// Session-aware redirects:
/// - signed-in users never see the welcome / sign-in / sign-up screens;
/// - setting a new password requires the session from a verified reset code;
/// - the verification screen needs its arguments (lost on a web refresh).
String? _redirect(AuthRepository auth, GoRouterState state) {
  final location = state.matchedLocation;
  final signedIn = auth.currentUser != null;

  if (signedIn && AppRoutes.guestOnly.contains(location)) {
    return AppRoutes.home;
  }
  if (!signedIn && location == AppRoutes.newPassword) {
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
  final subscription = auth.authStateChanges().listen((_) => refresh.notify());

  final router = GoRouter(
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
      GoRoute(
        path: AppRoutes.home,
        name: 'home',
        builder: (context, state) => const TemporaryHomeScreen(),
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
