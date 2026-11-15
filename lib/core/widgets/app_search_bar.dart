import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_shadows.dart';
import '../theme/app_typography.dart';
import 'app_icon_button.dart';

/// Pill-shaped search field with an optional blue filter button.
///
/// Set [readOnly] with [onTap] to use it as a button that opens a search
/// screen (as on the home screen).
class AppSearchBar extends StatelessWidget {
  const AppSearchBar({
    super.key,
    this.controller,
    this.hint = 'Search for services or domestic workers...',
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.onFilterPressed,
    this.readOnly = false,
    this.autofocus = false,
  });

  static const double height = 52;

  final TextEditingController? controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;

  /// Shows the filter button when set.
  final VoidCallback? onFilterPressed;

  final bool readOnly;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    const noBorder = OutlineInputBorder(
      borderRadius: AppRadius.pillAll,
      borderSide: BorderSide.none,
    );
    final filter = onFilterPressed;

    return Row(
      children: [
        Expanded(
          child: Container(
            height: height,
            decoration: const BoxDecoration(
              color: AppColors.white,
              borderRadius: AppRadius.pillAll,
              boxShadow: AppShadows.soft,
            ),
            child: TextField(
              controller: controller,
              readOnly: readOnly,
              autofocus: autofocus,
              onTap: onTap,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              textInputAction: TextInputAction.search,
              style: AppTypography.bodyMedium,
              decoration: InputDecoration(
                hintText: hint,
                prefixIcon: const Icon(Icons.search_rounded, size: 22),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                fillColor: AppColors.white,
                border: noBorder,
                enabledBorder: noBorder,
                focusedBorder: const OutlineInputBorder(
                  borderRadius: AppRadius.pillAll,
                  borderSide: BorderSide(color: AppColors.primary, width: 1.5),
                ),
              ),
            ),
          ),
        ),
        if (filter != null) ...[
          const SizedBox(width: 12),
          AppIconButton(
            icon: Icons.tune_rounded,
            tooltip: 'Filters',
            style: AppIconButtonStyle.primary,
            size: height,
            onPressed: filter,
          ),
        ],
      ],
    );
  }
}
