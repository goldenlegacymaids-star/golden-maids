import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

/// One tab of the bottom navigation.
class AppNavItem {
  const AppNavItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
}

/// Floating, pill-shaped bottom navigation with a frosted-glass look:
/// translucent background, backdrop blur, a fine light border and a soft
/// shadow. Every tab shows its icon and label; the active tab sits in a
/// light translucent capsule that slides between tabs, the others are grey.
class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  static const double barHeight = 68;

  /// Inactive tabs: grey, still readable on the frosted background.
  static const Color inactiveColor = Color(0xFF5F6875);

  final List<AppNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final animate = !MediaQuery.disableAnimationsOf(context);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.xxs,
        ),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            // Keeps the bar compact on tablets and web.
            constraints: const BoxConstraints(maxWidth: 480),
            child: DecoratedBox(
              // The shadow sits outside the blurred, clipped glass.
              decoration: const BoxDecoration(
                borderRadius: AppRadius.pillAll,
                boxShadow: [
                  BoxShadow(
                    color: Color(0x1A1B2A44),
                    blurRadius: 30,
                    offset: Offset(0, 12),
                  ),
                  BoxShadow(
                    color: Color(0x0D1B2A44),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: AppRadius.pillAll,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                  child: Container(
                    height: barHeight,
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      borderRadius: AppRadius.pillAll,
                      border: Border.all(
                        color: AppColors.white.withValues(alpha: 0.75),
                      ),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.white.withValues(alpha: 0.78),
                          AppColors.white.withValues(alpha: 0.6),
                        ],
                      ),
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final tabWidth = constraints.maxWidth / items.length;
                        return Stack(
                          children: [
                            // The active tab's capsule, sliding between tabs.
                            AnimatedPositioned(
                              duration: animate
                                  ? const Duration(milliseconds: 260)
                                  : Duration.zero,
                              curve: Curves.easeOutCubic,
                              left: tabWidth * currentIndex,
                              top: 0,
                              bottom: 0,
                              width: tabWidth,
                              child: const _ActiveCapsule(),
                            ),
                            // Taps ripple on the glass, not behind it.
                            Material(
                              type: MaterialType.transparency,
                              child: Row(
                                children: [
                                  for (var i = 0; i < items.length; i++)
                                    Expanded(
                                      child: _NavButton(
                                        item: items[i],
                                        selected: i == currentIndex,
                                        onTap: () => onTap(i),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Light, translucent rounded capsule behind the active tab.
class _ActiveCapsule extends StatelessWidget {
  const _ActiveCapsule();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: AppRadius.pillAll,
          color: AppColors.primary.withValues(alpha: 0.12),
          border: Border.all(color: AppColors.white.withValues(alpha: 0.9)),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.12),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final AppNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final iconColor = selected
        ? AppColors.primary
        : AppBottomNavBar.inactiveColor;
    final labelColor = selected
        ? AppColors.infoText
        : AppBottomNavBar.inactiveColor;

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        splashColor: AppColors.primary.withValues(alpha: 0.08),
        highlightColor: Colors.transparent,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              selected ? item.activeIcon : item.icon,
              color: iconColor,
              size: 23,
            ),
            const SizedBox(height: 2),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelSmall.copyWith(
                color: labelColor,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
