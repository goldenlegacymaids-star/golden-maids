import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/onboarding/presentation/splash_screen.dart';
import '../config/env.dart';
import 'app_routes.dart';
import 'design_preview_screen.dart';

/// The app's single [GoRouter] instance.
final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: !Env.isProduction,
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
      // TEMPORARY destination after onboarding until Step 1.5 (sign-in).
      // From Step 1.5 it is available in development builds only.
      GoRoute(
        path: AppRoutes.designPreview,
        name: 'design-preview',
        builder: (context, state) => const DesignPreviewScreen(),
      ),
    ],
  );

  ref.onDispose(router.dispose);
  return router;
});
