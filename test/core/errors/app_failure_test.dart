import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:golden_maids/core/errors/app_failure.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('AppFailure.from', () {
    test('returns an AppFailure unchanged', () {
      const failure = NotFoundFailure();
      expect(AppFailure.from(failure), same(failure));
    });

    test('timeouts and connection errors become NetworkFailure', () {
      expect(AppFailure.from(TimeoutException('slow')), isA<NetworkFailure>());
      expect(
        AppFailure.from(Exception('ClientException: Failed host lookup')),
        isA<NetworkFailure>(),
      );
      expect(
        AppFailure.from(AuthRetryableFetchException()),
        isA<NetworkFailure>(),
      );
    });

    test('database permission errors become PermissionFailure', () {
      const error = PostgrestException(message: 'denied', code: '42501');
      expect(AppFailure.from(error), isA<PermissionFailure>());
    });

    test('missing rows become NotFoundFailure', () {
      const error = PostgrestException(message: 'none', code: 'PGRST116');
      expect(AppFailure.from(error), isA<NotFoundFailure>());
    });

    test('expired tokens become AuthFailure', () {
      const error = PostgrestException(message: 'jwt', code: 'PGRST303');
      expect(AppFailure.from(error), isA<AuthFailure>());
      expect(
        AppFailure.from(AuthSessionMissingException()),
        isA<AuthFailure>(),
      );
    });

    test('constraint errors become ValidationFailure', () {
      expect(
        AppFailure.from(
          const PostgrestException(message: 'dup', code: '23505'),
        ),
        isA<ValidationFailure>(),
      );
      expect(
        AppFailure.from(
          const PostgrestException(message: 'check', code: '23514'),
        ),
        isA<ValidationFailure>(),
      );
    });

    test('database rule messages are shown; raw constraint text is not', () {
      expect(
        AppFailure.from(
          const PostgrestException(
            message: 'This candidate is no longer listed.',
            code: '23514',
          ),
        ).message,
        'This candidate is no longer listed.',
      );
      expect(
        AppFailure.from(
          const PostgrestException(
            message: 'new row for relation "x" violates check constraint "y"',
            code: '23514',
          ),
        ).message,
        'Some of the details are not valid. Please check and try again.',
      );
    });

    test('database refusals show their message; raw permission errors do '
        'not', () {
      expect(
        AppFailure.from(
          const PostgrestException(
            message: 'You can only cancel a request that has not been '
                'processed yet.',
            code: '42501',
          ),
        ).message,
        'You can only cancel a request that has not been processed yet.',
      );
      expect(
        AppFailure.from(
          const PostgrestException(
            message: 'permission denied for table hiring_requests',
            code: '42501',
          ),
        ).message,
        const PermissionFailure().message,
      );
      expect(
        AppFailure.from(
          const PostgrestException(
            message: 'new row violates row-level security policy',
            code: '42501',
          ),
        ).message,
        const PermissionFailure().message,
      );
    });

    test('auth messages are passed through for the user', () {
      final failure = AppFailure.from(
        const AuthException('Invalid login credentials', statusCode: '400'),
      );
      expect(failure, isA<AuthFailure>());
      expect(failure.message, 'Invalid login credentials');
    });

    test('storage errors are mapped by status code', () {
      expect(
        AppFailure.from(const StorageException('no', statusCode: '403')),
        isA<PermissionFailure>(),
      );
      expect(
        AppFailure.from(const StorageException('gone', statusCode: '404')),
        isA<NotFoundFailure>(),
      );
    });

    test('anything else becomes UnknownFailure and keeps the cause', () {
      final error = StateError('boom');
      final failure = AppFailure.from(error);
      expect(failure, isA<UnknownFailure>());
      expect(failure.cause, same(error));
    });
  });
}
