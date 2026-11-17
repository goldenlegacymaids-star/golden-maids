import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'skeleton.dart';

/// Network image with disk caching, a shimmer placeholder while loading and
/// a fallback when the image is missing or fails to load.
///
/// Images are decoded at the size they are displayed, to save memory.
class AppNetworkImage extends StatelessWidget {
  const AppNetworkImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.borderRadius = BorderRadius.zero,
    this.semanticLabel,
  });

  final String? url;
  final double? width;
  final double? height;
  final BoxFit fit;

  /// Which part stays in view when [fit] crops the image.
  final Alignment alignment;
  final BorderRadius borderRadius;

  /// Describes the image for screen readers.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final imageUrl = url;
    const fallback = ColoredBox(
      color: AppColors.lightBlue,
      child: Center(
        child: Icon(
          Icons.image_outlined,
          color: AppColors.textSecondary,
          size: 28,
        ),
      ),
    );

    final Widget image = (imageUrl == null || imageUrl.isEmpty)
        ? fallback
        : LayoutBuilder(
            builder: (context, constraints) {
              final pixelRatio = MediaQuery.devicePixelRatioOf(context);
              final int? cacheWidth = constraints.hasBoundedWidth
                  ? (constraints.maxWidth * pixelRatio).round()
                  : null;

              return CachedNetworkImage(
                imageUrl: imageUrl,
                width: width,
                height: height,
                fit: fit,
                alignment: alignment,
                memCacheWidth: cacheWidth,
                fadeInDuration: const Duration(milliseconds: 200),
                placeholder: (_, _) => const Skeleton(
                  child: SkeletonBox(borderRadius: BorderRadius.zero),
                ),
                errorWidget: (_, _, _) => fallback,
              );
            },
          );

    return Semantics(
      image: true,
      label: semanticLabel,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: SizedBox(width: width, height: height, child: image),
      ),
    );
  }
}
