import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';

/// Shimmer effect for loading placeholders. Wrap one or more [SkeletonBox]es.
class Skeleton extends StatelessWidget {
  const Skeleton({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading',
      child: ExcludeSemantics(
        child: Shimmer.fromColors(
          baseColor: AppColors.lightBlue,
          highlightColor: AppColors.veryLightBlue,
          child: child,
        ),
      ),
    );
  }
}

/// A grey-blue block shaped like the content that is loading.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.borderRadius = AppRadius.smAll,
  });

  /// Circle placeholder, e.g. for avatars.
  const SkeletonBox.circle({super.key, required double size})
    : width = size,
      height = size,
      borderRadius = AppRadius.pillAll;

  final double? width;
  final double? height;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.lightBlue,
        borderRadius: borderRadius,
      ),
    );
  }
}
