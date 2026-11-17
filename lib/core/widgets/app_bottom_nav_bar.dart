import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../haptics/haptics.dart';
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

/// Floating, pill-shaped bottom navigation with a frosted-glass look: a
/// neutral, see-through grey background with backdrop blur, a fine light
/// border and a soft shadow. Every tab shows a line icon and its label; the
/// active tab sits in a light translucent capsule (sliding between tabs) and
/// is drawn darker, the others are grey.
class AppBottomNavBar extends StatelessWidget {
  const AppBottomNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  static const double barHeight = 64;

  /// Inactive tabs: grey, still readable on the frosted background.
  static const Color inactiveColor = Color(0xFF5F6670);

  /// The active tab: near-black ink.
  static const Color activeColor = Color(0xFF22262E);

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
          AppSpacing.sm,
          0,
          AppSpacing.sm,
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
                    color: Color(0x24000000),
                    blurRadius: 24,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: AppRadius.pillAll,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    height: barHeight,
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      borderRadius: AppRadius.pillAll,
                      border: Border.all(
                        color: AppColors.white.withValues(alpha: 0.55),
                      ),
                      // Neutral smoky glass: the page shows through.
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0x8CE4E6EA), Color(0x99D6D9DE)],
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
                                        onTap: () {
                                          if (i != currentIndex) {
                                            haptic(
                                              context,
                                              HapticKind.selection,
                                            );
                                          }
                                          onTap(i);
                                        },
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
          color: AppColors.white.withValues(alpha: 0.72),
          border: Border.all(color: AppColors.white.withValues(alpha: 0.9)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 8,
              offset: Offset(0, 2),
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
    final color = selected
        ? AppBottomNavBar.activeColor
        : AppBottomNavBar.inactiveColor;

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        splashColor: AppColors.white.withValues(alpha: 0.3),
        highlightColor: Colors.transparent,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Line icons on every tab; the active one is darker.
            Icon(item.icon, color: color, size: 24),
            const SizedBox(height: 2),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.labelSmall.copyWith(
                color: color,
                fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
