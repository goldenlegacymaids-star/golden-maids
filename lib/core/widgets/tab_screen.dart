import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// Layout for a main tab: soft blue wash, a large title and scrollable
/// content that stays clear of the floating bottom navigation.
class TabScreen extends StatelessWidget {
  const TabScreen({
    super.key,
    required this.title,
    required this.child,
    this.scrollable = true,
  });

  final String title;
  final Widget child;

  /// Set false when [child] scrolls by itself (e.g. contains a TabBarView).
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    // Includes the height of the floating bottom navigation (Scaffold.extendBody).
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    final header = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.screenPadding,
        AppSpacing.md,
        AppSpacing.screenPadding,
        AppSpacing.md,
      ),
      child: Semantics(
        header: true,
        child: Text(title, style: AppTypography.headlineMedium),
      ),
    );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: AppColors.white,
        body: DecoratedBox(
          decoration: const BoxDecoration(gradient: AppColors.backgroundWash),
          child: SafeArea(
            bottom: false,
            child: scrollable
                ? ListView(
                    padding: EdgeInsets.only(bottom: bottomInset + AppSpacing.xl),
                    children: [header, child],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      header,
                      Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(bottom: bottomInset),
                          child: child,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
