import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_shadows.dart';

enum AppIconButtonStyle {
  /// White circle with a soft shadow (notification bell, back button).
  light,

  /// Blue circle with a white icon (search filter).
  primary,

  /// Dark see-through circle, for use on top of photos.
  translucent,
}

/// Circular icon button.
class AppIconButton extends StatelessWidget {
  const AppIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.style = AppIconButtonStyle.light,
    this.size = 48,
    this.showBadge = false,
  });

  final IconData icon;

  /// Shown on long-press and read by screen readers. Always required.
  final String tooltip;

  final VoidCallback? onPressed;
  final AppIconButtonStyle style;
  final double size;

  /// Small red dot, e.g. for unread notifications.
  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    final (Color background, Color foreground) = switch (style) {
      AppIconButtonStyle.light => (AppColors.white, AppColors.textPrimary),
      AppIconButtonStyle.primary => (AppColors.primary, AppColors.white),
      AppIconButtonStyle.translucent => (
        const Color(0x59202631),
        AppColors.white,
      ),
    };

    final button = DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: style == AppIconButtonStyle.light ? AppShadows.soft : null,
      ),
      child: Material(
        color: background,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: size * 0.46, color: foreground),
          ),
        ),
      ),
    );

    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        child: showBadge
            ? Stack(
                clipBehavior: Clip.none,
                children: [
                  button,
                  Positioned(
                    top: size * 0.22,
                    right: size * 0.24,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: AppColors.error,
                        shape: BoxShape.circle,
                        border: Border.all(color: background, width: 1.5),
                      ),
                    ),
                  ),
                ],
              )
            : button,
      ),
    );
  }
}
