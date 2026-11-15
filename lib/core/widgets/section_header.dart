import 'package:flutter/material.dart';

import '../theme/app_typography.dart';

/// Section title with an optional "View All" link (e.g. "Featured Maids").
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.actionLabel = 'View All',
    this.onAction,
  });

  final String title;
  final String actionLabel;

  /// Shows the action link when set.
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final action = onAction;

    return Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(title, style: AppTypography.headlineSmall),
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: action,
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 40),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              textStyle: AppTypography.labelMedium,
            ),
            child: Text(actionLabel),
          ),
      ],
    );
  }
}
