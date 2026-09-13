import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/views/opt_view/widgets/otp_code_field.dart';

/// `OtpCodeField` is drawn as six boxes but driven by ONE hidden text field, so
/// it edits like a single input: digits fill left-to-right and backspace walks
/// back through every box (the user should never have to tap each box to clear
/// a mistake).
void main() {
  Widget host({required ValueChanged<String> onChanged, bool enabled = true}) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          child: OtpCodeField(
            codeLength: 6,
            enabled: enabled,
            onChanged: onChanged,
          ),
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

  testWidgets('a disabled field keeps the digits and ignores backspace', (
    WidgetTester tester,
  ) async {
    // The OTP screen locks the boxes while the code is being verified, so a
    // backspace cannot delete a digit out of a request already in flight.
    final List<String> codes = <String>[];
    await tester.pumpWidget(host(onChanged: codes.add));

    await tester.showKeyboard(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();
    expect(codes.last, '123456');

    await tester.pumpWidget(host(enabled: false, onChanged: codes.add));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    final TextField field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isFalse);
    // The code survives: the boxes still show all six digits and no new value
    // was reported to the screen.
    expect(field.controller!.text, '123456');
    expect(codes.last, '123456');
  });

  testWidgets('unlocking the field again lets backspace work once more', (
    WidgetTester tester,
  ) async {
    // A rejected code re-enables the boxes, so the tourist can correct it.
    final List<String> codes = <String>[];
    await tester.pumpWidget(host(onChanged: codes.add));

    await tester.showKeyboard(find.byType(TextField));
    await tester.enterText(find.byType(TextField), '123456');
    await tester.pump();

    await tester.pumpWidget(host(enabled: false, onChanged: codes.add));
    await tester.pump();
    await tester.pumpWidget(host(onChanged: codes.add));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump();

    expect(codes.last, '12345');
  });
}
