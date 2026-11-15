import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A problem the user should be told about, with a clear title and message.
///
/// Repositories catch technical errors and convert them with
/// [AppFailure.from], so screens never show raw exception text.
sealed class AppFailure implements Exception {
  const AppFailure({required this.title, required this.message, this.cause});

  /// Converts any error into an [AppFailure].
  factory AppFailure.from(Object error) {
    return switch (error) {
      final AppFailure failure => failure,
      final TimeoutException timeout => NetworkFailure(cause: timeout),
      final AuthException auth => _fromAuth(auth),
      final PostgrestException postgrest => _fromPostgrest(postgrest),
      final StorageException storage => _fromStorage(storage),
      _ when _looksLikeNetworkError(error) => NetworkFailure(cause: error),
      _ => UnknownFailure(cause: error),
    };
  }

  static AppFailure _fromAuth(AuthException error) {
    if (error is AuthRetryableFetchException) {
      return NetworkFailure(cause: error);
    }
    if (error is AuthSessionMissingException ||
        error is AuthInvalidJwtException ||
        error.statusCode == '401') {
      return AuthFailure(
        message: 'Your session has expired. Please sign in again.',
        cause: error,
      );
    }
    // Supabase Auth messages are written for end users
    // (e.g. "Invalid login credentials").
    return AuthFailure(message: error.message, cause: error);
  }

  static AppFailure _fromPostgrest(PostgrestException error) {
    return switch (error.code) {
      // Row Level Security / missing privilege.
      '42501' => PermissionFailure(cause: error),
      // .single() found no row.
      'PGRST116' => NotFoundFailure(cause: error),
      // Expired or invalid session token.
      'PGRST301' || 'PGRST303' => AuthFailure(
        message: 'Your session has expired. Please sign in again.',
        cause: error,
      ),
      // Unique constraint.
      '23505' => ValidationFailure(
        message: 'This record already exists.',
        cause: error,
      ),
      // Check / not-null / foreign-key / bad input format.
      '23514' || '23502' || '23503' || '22P02' => ValidationFailure(
        message: 'Some of the details are not valid. Please check and try again.',
        cause: error,
      ),
      _ => ServerFailure(cause: error),
    };
  }

  static AppFailure _fromStorage(StorageException error) {
    return switch (error.statusCode) {
      '401' || '403' => PermissionFailure(cause: error),
      '404' => NotFoundFailure(cause: error),
      _ => ServerFailure(cause: error),
    };
  }

  /// HTTP-level connection errors come from the `http` package (and
  /// `dart:io` on mobile), which the app does not import directly, so they
  /// are recognised by name.
  static bool _looksLikeNetworkError(Object error) {
    final text = error.toString();
    return text.contains('SocketException') ||
        text.contains('ClientException') ||
        text.contains('Failed host lookup') ||
        text.contains('XMLHttpRequest error') ||
        text.contains('Connection refused') ||
        text.contains('Network is unreachable');
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
