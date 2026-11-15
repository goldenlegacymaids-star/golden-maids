import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_maids/core/theme/app_theme.dart';
import 'package:golden_maids/core/widgets/app_button.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );
}

void main() {
  testWidgets('shows a spinner and ignores repeat taps while busy', (
    tester,
  ) async {
    final completer = Completer<void>();
    var taps = 0;

    await tester.pumpWidget(
      _wrap(
        AppButton(
          label: 'Book Now',
          onPressed: () {
            taps++;
            return completer.future;
          },
        ),
      ),
    );

    await tester.tap(find.text('Book Now'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Book Now'), findsNothing);

    // Repeat taps while busy must be ignored.
    await tester.tap(find.byType(AppButton));
    await tester.tap(find.byType(AppButton));
    await tester.pump();
    expect(taps, 1);

    completer.complete();
    await tester.pumpAndSettle();
    expect(find.text('Book Now'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('isLoading shows a spinner and blocks taps', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _wrap(AppButton(label: 'Pay', isLoading: true, onPressed: () => taps++)),
    );

    await tester.tap(find.byType(AppButton));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(taps, 0);
  });

  testWidgets('is disabled when onPressed is null', (tester) async {
    await tester.pumpWidget(
      _wrap(const AppButton(label: 'Submit', onPressed: null)),
    );

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });
}
