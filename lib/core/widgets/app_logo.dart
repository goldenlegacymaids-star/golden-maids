import 'package:flutter/material.dart';

import '../constants/app_assets.dart';
import '../constants/app_constants.dart';

/// The Golden Maids logo.
class AppLogo extends StatelessWidget {
  /// Icon + "Golden Maids" wordmark + tagline.
  const AppLogo.full({super.key, this.height = 56, this.onDark = false})
    : _iconOnly = false;

  /// The square app icon only.
  const AppLogo.icon({super.key, double size = 56, this.onDark = false})
    : height = size,
      _iconOnly = true;

  final double height;

  /// Use the white version, for blue backgrounds.
  final bool onDark;

  final bool _iconOnly;

  /// Width / height of the full logo artwork.
  static const double _fullAspectRatio = 465 / 120;

  @override
  Widget build(BuildContext context) {
    final String asset = _iconOnly
        ? (onDark ? AppAssets.logoIconWhite : AppAssets.logoIcon)
        : (onDark ? AppAssets.logoFullWhite : AppAssets.logoFull);

    return Image.asset(
      asset,
      height: height,
      width: _iconOnly ? height : height * _fullAspectRatio,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      semanticLabel: '${AppConstants.appName} logo',
    );
  }
}
