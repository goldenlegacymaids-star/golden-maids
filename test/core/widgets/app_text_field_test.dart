import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_maids/core/theme/app_theme.dart';
import 'package:golden_maids/core/widgets/app_text_field.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );
}

String? _requiredEmail(String? value) {
  return (value == null || value.isEmpty) ? 'Email is required' : null;
}

void main() {
  testWidgets('shows the error on submit and clears it when fixed', (
    tester,
  ) async {
    final formKey = GlobalKey<FormState>();
    await tester.pumpWidget(
      _wrap(
        Form(
          key: formKey,
          child: const AppTextField(label: 'Email', validator: _requiredEmail),
        ),
      ),
    );

    expect(find.text('Email is required'), findsNothing);

    expect(formKey.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('Email is required'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField), 'sarah@example.com');
    await tester.pump();
    expect(find.text('Email is required'), findsNothing);
  });

  testWidgets('password field hides text and can be toggled', (tester) async {
    await tester.pumpWidget(
      _wrap(const AppTextField(label: 'Password', obscureText: true)),
    );

    EditableText editable() =>
        tester.widget<EditableText>(find.byType(EditableText));

    expect(editable().obscureText, isTrue);

    await tester.tap(find.byTooltip('Show password'));
    await tester.pump();
    expect(editable().obscureText, isFalse);

    await tester.tap(find.byTooltip('Hide password'));
    await tester.pump();
    expect(editable().obscureText, isTrue);
  });
}
