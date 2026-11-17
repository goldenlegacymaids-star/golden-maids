import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/haptics/haptics.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// Profile → Vibration: turns the app's haptic feedback on or off.
class VibrationTile extends ConsumerWidget {
  const VibrationTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(hapticsEnabledProvider);
    return MergeSemantics(
      child: SwitchListTile.adaptive(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        secondary: Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: AppColors.lightBlue,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.vibration_rounded,
            size: 20,
            color: AppColors.primary,
          ),
        ),
        title: Text(
          'Vibration',
          style: AppTypography.bodyLarge.copyWith(
            color: AppColors.textPrimary,
          ),
        ),
        subtitle: const Text(
          'Gentle vibrations on taps, and when something is sent',
          style: AppTypography.bodySmall,
        ),
        value: enabled,
        onChanged: (on) async {
          await ref.read(hapticsEnabledProvider.notifier).setEnabled(on);
          // A tick to show what "on" feels like.
          if (on && context.mounted) haptic(context, HapticKind.selection);
        },
      ),
    );
  }
}
