import 'package:flutter/widgets.dart';

/// Spacing scale (multiples of 4).
abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 40;

  /// Horizontal padding used by every screen.
  static const double screenPadding = 20;

  static const EdgeInsets screen = EdgeInsets.symmetric(
    horizontal: screenPadding,
  );
}
