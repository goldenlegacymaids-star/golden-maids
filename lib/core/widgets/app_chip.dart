import 'package:flutter/material.dart';

import '../haptics/haptics.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Pill-shaped selectable chip (category filters such as "All", "Cleaning").
class AppChip extends StatelessWidget {
  const AppChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.leading,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;
  final IconData? icon;

  /// Shown instead of [icon], e.g. a small flag.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? AppColors.white : AppColors.textPrimary;
    final tap = onTap;
    final shape = StadiumBorder(
      side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
    );
    final chipIcon = icon;
    final leadingWidget = leading;

    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.primary : AppColors.white,
        shape: shape,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: tap == null
              ? null
              : () {
                  haptic(context, HapticKind.selection);
                  tap();
                },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leadingWidget != null) ...[
                  leadingWidget,
                  const SizedBox(width: 6),
                ] else if (chipIcon != null) ...[
                  Icon(chipIcon, size: 18, color: foreground),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: AppTypography.labelMedium.copyWith(color: foreground),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
