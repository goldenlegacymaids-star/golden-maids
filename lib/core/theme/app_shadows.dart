import 'package:flutter/painting.dart';

/// Soft shadows, tinted with the primary text colour.
abstract final class AppShadows {
  /// Subtle lift for small elements (chips, icon buttons).
  static const List<BoxShadow> soft = [
    BoxShadow(color: Color(0x0D202631), blurRadius: 12, offset: Offset(0, 4)),
  ];

  /// Standard card shadow.
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x12202631), blurRadius: 24, offset: Offset(0, 8)),
  ];

  /// Floating elements (bottom navigation, sticky action bars).
  static const List<BoxShadow> floating = [
    BoxShadow(color: Color(0x1F202631), blurRadius: 32, offset: Offset(0, 12)),
  ];
}
