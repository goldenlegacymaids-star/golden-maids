import 'dart:async';

import 'package:flutter/material.dart';

/// A problem the user should be told about, with a clear title and message.
///
/// Repositories catch technical errors and convert them with
/// [AppFailure.from], so screens never show raw exception text.
/// Mappings for Supabase errors are added in Step 1.3.
sealed class AppFailure implements Exception {
  const AppFailure({required this.title, required this.message, this.cause});

  /// Converts any error into an [AppFailure].
  factory AppFailure.from(Object error) {
    if (error is AppFailure) return error;
    if (error is TimeoutException) return NetworkFailure(cause: error);
    return UnknownFailure(cause: error);
  }

  final String title;
  final String message;

  /// The original error, kept for logging. Never shown to users.
  final Object? cause;

  IconData get icon;

  @override
  String toString() => 'AppFailure($title: $message, cause: $cause)';
}

class NetworkFailure extends AppFailure {
  const NetworkFailure({
    super.message = 'Please check your internet connection and try again.',
    super.cause,
  }) : super(title: 'No connection');

  @override
  IconData get icon => Icons.wifi_off_rounded;
}

class AuthFailure extends AppFailure {
  const AuthFailure({
    super.message = 'Please sign in to continue.',
    super.cause,
  }) : super(title: 'Sign in required');

  @override
  IconData get icon => Icons.lock_outline_rounded;
}

class PermissionFailure extends AppFailure {
  const PermissionFailure({
    super.message = "You don't have permission to access this.",
    super.cause,
  }) : super(title: 'Access denied');

  @override
  IconData get icon => Icons.block_rounded;
}

class NotFoundFailure extends AppFailure {
  const NotFoundFailure({
    super.message = "We couldn't find what you were looking for.",
    super.cause,
  }) : super(title: 'Not found');

  @override
  IconData get icon => Icons.search_off_rounded;
}

class ValidationFailure extends AppFailure {
  const ValidationFailure({required super.message, super.cause})
    : super(title: 'Please check your details');

  @override
  IconData get icon => Icons.error_outline_rounded;
}

class ServerFailure extends AppFailure {
  const ServerFailure({
    super.message = 'Something went wrong on our side. Please try again.',
    super.cause,
  }) : super(title: 'Service unavailable');

  @override
  IconData get icon => Icons.cloud_off_rounded;
}

class UnknownFailure extends AppFailure {
  const UnknownFailure({
    super.message =
        'Please try again. If the problem continues, contact support.',
    super.cause,
  }) : super(title: 'Something went wrong');

  @override
  IconData get icon => Icons.error_outline_rounded;
}
