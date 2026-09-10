import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/views/opt_view/widgets/otp_code_field.dart';

/// `OtpCodeField` is drawn as six boxes but driven by ONE hidden text field, so
/// it edits like a single input: digits fill left-to-right and backspace walks
/// back through every box (the user should never have to tap each box to clear
/// a mistake).
void main() {
  Widget host({required ValueChanged<String> onChanged}) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          child: OtpCodeField(codeLength: 6, onChanged: onChanged),
        ),
      ),
    );
  }

  testWidgets('types digits left-to-right and reports the whole code', (
    WidgetTester tester,
  ) async {
    final List<String> codes = <String>[];
    await tester.pumpWidget(host(onChanged: codes.add));

    // The single hidden field owns input; typing fills the boxes.
    await tester.showKeyboard(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '123');
    await tester.pump();

    expect(codes.last, '123');

    // The six visible boxes mirror the hidden field's text. Read the value
    // through the controller AND check a digit appears in the box layer.
    final TextField field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '123');
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    // No stray fourth digit.
    expect(find.text('4'), findsNothing);
  });

  testWidgets('backspace removes the last digit and keeps walking back', (
    WidgetTester tester,
  ) async {
    final List<String> codes = <String>[];
    await tester.pumpWidget(host(onChanged: codes.add));

    await tester.showKeyboard(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    expect(codes.last, '123456');

    // A single TextField treats backspace like one input field: each press
    // deletes the last digit regardless of "which box" the caret is in.
    final List<String> expected = <String>[
      '12345',
      '1234',
      '123',
      '12',
      '1',
      '',
    ];
    for (final String next in expected) {
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(codes.last, next);
    }

    // Fully cleared - typing again starts from the first box.
    await tester.enterText(find.byType(TextField), '9');
    expect(codes.last, '9');
  });

  testWidgets('ignores non-digit input', (WidgetTester tester) async {
    final List<String> codes = <String>[];
    await tester.pumpWidget(host(onChanged: codes.add));

    await tester.showKeyboard(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'a1b2');

    expect(codes.last, '12');
  });
}
