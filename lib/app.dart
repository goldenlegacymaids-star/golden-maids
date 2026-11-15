import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'core/routing/app_router.dart';

/// Root widget of the Golden Maids app.
class GoldenMaidsApp extends ConsumerWidget {
  const GoldenMaidsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      // Temporary theme. Replaced by the full design system in Step 1.2.
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF398FF2)),
      ),
      routerConfig: router,
    );
  }
}
