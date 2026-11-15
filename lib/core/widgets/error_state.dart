import 'dart:async';

import 'package:flutter/material.dart';

import '../errors/app_failure.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'app_button.dart';

/// Shown when loading fails. Offers a retry button.
class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.failure, this.onRetry});

  final AppFailure failure;

  /// Shows a "Try again" button when set. May return a Future; the button
  /// shows a spinner until it completes.
  final FutureOr<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final retry = onRetry;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(
                color: Color(0x1AE65353),
                shape: BoxShape.circle,
              ),
              child: Icon(failure.icon, size: 40, color: AppColors.error),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              failure.title,
              style: AppTypography.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              failure.message,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            if (retry != null) ...[
              const SizedBox(height: AppSpacing.xl),
              AppButton(
                label: 'Try again',
                icon: Icons.refresh_rounded,
                variant: AppButtonVariant.outline,
                expand: false,
                onPressed: retry,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
