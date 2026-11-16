import 'package:flutter/painting.dart';

/// Golden Maids colour palette.
///
/// Always use these constants. Never type hex colours inside widgets.
abstract final class AppColors {
  // Brand blues
  static const Color primary = Color(0xFF398FF2);
  static const Color secondary = Color(0xFF2F83E8);
  static const Color lightBlue = Color(0xFFEAF3FF);
  static const Color veryLightBlue = Color(0xFFF4F8FF);

  // Neutrals
  static const Color white = Color(0xFFFFFFFF);
  // Softer than near-black: Outfit reads heavier than the previous fonts.
  static const Color textPrimary = Color(0xFF3A4352);
  static const Color textSecondary = Color(0xFF7B8491);
  static const Color border = Color(0xFFE5EAF1);

  // Status
  static const Color success = Color(0xFF25B875);
  static const Color warning = Color(0xFFF3B642);
  static const Color error = Color(0xFFE65353);

  /// Golden accent. Only for the logo sparkle and small highlights such as
  /// rating stars. Never use it as a background.
  static const Color gold = warning;

  /// Near-black. Only for the call-to-action button on blue promo banners.
  static const Color ink = Color(0xFF15181E);

  /// Overlay behind dialogs and bottom sheets.
  static const Color scrim = Color(0x66202631);

  /// Screen background: soft blue at the top, fading to [veryLightBlue] so
  /// white cards and fields stand out.
  static const LinearGradient backgroundWash = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [washTop, lightBlue, veryLightBlue, veryLightBlue],
    stops: [0, 0.3, 0.6, 1],
  );

  /// Top of the background wash: a little deeper than [lightBlue].
  static const Color washTop = Color(0xFFD6E8FF);
}
