import 'package:flutter/material.dart';

import '../haptics/haptics.dart';

/// Pull-to-refresh with a firm tap when the refresh starts.
class AppRefreshIndicator extends StatelessWidget {
  const AppRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  final RefreshCallback onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () {
        haptic(context, HapticKind.medium);
        return onRefresh();
      },
      child: child,
    );
  }
}
