import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../config/env.dart';
import 'app_routes.dart';
import 'design_preview_screen.dart';

/// The app's single [GoRouter] instance.
final appRouterProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: AppRoutes.start,
    debugLogDiagnostics: !Env.isProduction,
    routes: [
      GoRoute(
        path: AppRoutes.start,
        name: 'start',
        // TEMPORARY: design preview. Replaced by the splash screen in Step 1.4.
        builder: (context, state) => const DesignPreviewScreen(),
      ),
    ],
  );

  ref.onDispose(router.dispose);
  return router;
});
