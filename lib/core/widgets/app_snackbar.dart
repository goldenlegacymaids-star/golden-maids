import 'package:flutter/material.dart';

import '../errors/app_failure.dart';
import '../theme/app_colors.dart';

/// Shows a short message at the bottom of the screen.
void showAppSnackBar(
  BuildContext context,
  String message, {
  bool isError = false,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.error : null,
      ),
    );
}

/// Shows the user-friendly message for any error.
void showErrorSnackBar(BuildContext context, Object error) {
  showAppSnackBar(context, AppFailure.from(error).message, isError: true);
}
