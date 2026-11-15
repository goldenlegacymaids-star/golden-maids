import 'package:flutter/material.dart';

import '../config/env.dart';
import '../constants/app_constants.dart';

/// TEMPORARY start screen confirming the project skeleton runs.
///
/// Deleted in Step 1.4, when the splash screen becomes the first route.
class StartPlaceholderScreen extends StatelessWidget {
  const StartPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(AppConstants.appName, style: textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(AppConstants.tagline, style: textTheme.bodyLarge),
                const SizedBox(height: 32),
                Text(
                  'Step 1.1 – project setup complete',
                  style: textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  Env.isSupabaseConfigured
                      ? 'Backend settings: found'
                      : 'Backend settings: not set yet (Step 1.3)',
                  style: textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
