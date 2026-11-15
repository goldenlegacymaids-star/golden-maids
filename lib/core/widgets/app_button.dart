import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum AppButtonVariant {
  /// Blue filled pill: the main action on a screen.
  primary,

  /// Blue outlined pill: secondary actions.
  outline,

  /// Near-black filled pill: only for CTAs on blue promo banners.
  dark,

  /// Text-only: low-emphasis actions such as "Skip".
  text,
}

/// The app's standard button.
///
/// Duplicate-submission protection: if [onPressed] returns a [Future], the
/// button shows a spinner and ignores further taps until it completes.
/// Set [isLoading] to control the spinner from outside.
class AppButton extends StatefulWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.isLoading = false,
    this.expand = true,
    this.compact = false,
  });

  final String label;

  /// `null` disables the button.
  final FutureOr<void> Function()? onPressed;

  final AppButtonVariant variant;
  final IconData? icon;
  final bool isLoading;

  /// Stretch to the full available width.
  final bool expand;

  /// Smaller height (44 instead of 54), for buttons inside cards and banners.
  final bool compact;

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _busy = false;

  bool get _loading => widget.isLoading || _busy;

  Future<void> _handlePress() async {
    if (_loading) return;
    final result = widget.onPressed?.call();
    if (result is Future<void>) {
      setState(() => _busy = true);
      try {
        await result;
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
  }

  Color get _foreground => switch (widget.variant) {
    AppButtonVariant.primary || AppButtonVariant.dark => AppColors.white,
    AppButtonVariant.outline || AppButtonVariant.text => AppColors.primary,
  };

  Widget _buildChild() {
    if (_loading) {
      return Semantics(
        label: '${widget.label}, loading',
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: _foreground,
          ),
        ),
      );
    }

    final text = Text(
      widget.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    final icon = widget.icon;
    if (icon == null) return text;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Flexible(child: text),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final VoidCallback? onTap = widget.onPressed == null
        ? null
        : () => unawaited(_handlePress());

    final Size? minimumSize = widget.compact ? const Size(64, 44) : null;
    final EdgeInsetsGeometry? padding = widget.compact
        ? const EdgeInsets.symmetric(horizontal: 20)
        : null;
    final child = _buildChild();

    final Widget button = switch (widget.variant) {
      AppButtonVariant.primary => FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          minimumSize: minimumSize,
          padding: padding,
        ),
        child: child,
      ),
      AppButtonVariant.dark => FilledButton(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.ink,
          foregroundColor: AppColors.white,
          minimumSize: minimumSize,
          padding: padding,
        ),
        child: child,
      ),
      AppButtonVariant.outline => OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          minimumSize: minimumSize,
          padding: padding,
        ),
        child: child,
      ),
      AppButtonVariant.text => TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(minimumSize: minimumSize, padding: padding),
        child: child,
      ),
    };

    if (!widget.expand) return button;
    return SizedBox(width: double.infinity, child: button);
  }
}
