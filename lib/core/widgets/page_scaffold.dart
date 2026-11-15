import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../routing/app_routes.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import 'app_icon_button.dart';

/// Layout for inner pages: back button, title and body.
///
/// Inside the tab shell, content stays clear of the floating bottom
/// navigation automatically.
class PageScaffold extends StatelessWidget {
  const PageScaffold({
    super.key,
    required this.title,
    required this.body,
    this.trailing,
  });

  final String title;
  final Widget body;

  /// Optional widget at the right of the title row.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final trailingWidget = trailing;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: DecoratedBox(
          decoration: const BoxDecoration(gradient: AppColors.backgroundWash),
          child: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.sm,
                    AppSpacing.xs,
                    AppSpacing.screenPadding,
                    AppSpacing.xs,
                  ),
                  child: Row(
                    children: [
                      AppIconButton(
                        icon: Icons.arrow_back_rounded,
                        tooltip: 'Back',
                        size: 44,
                        onPressed: () => context.canPop()
                            ? context.pop()
                            : context.go(AppRoutes.home),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Text(
                            title,
                            style: AppTypography.titleLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      if (trailingWidget != null) trailingWidget,
                    ],
                  ),
                ),
                Expanded(child: body),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
