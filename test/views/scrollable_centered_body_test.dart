import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/views/common_widgets/scrollable_centered_body.dart';

/// The auth screens' keyboard-safe body must never overflow:
///  * content shorter than the viewport stays centred;
///  * content taller than the viewport (the software keyboard shrank it, or an
///    inline error row grew the form) scrolls instead of clipping.
void main() {
  Widget host({required double height, required List<Widget> children}) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          height: height,
          child: ScrollableCenteredBody(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: children,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('centres content that fits without overflowing', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(
        height: 600,
        children: <Widget>[
          const SizedBox(height: 100, child: Text('A')),
          const SizedBox(height: 200, child: Text('B')),
        ],
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('A'), findsOneWidget);
    expect(find.text('B'), findsOneWidget);
  });

  testWidgets('scrolls instead of overflowing when the viewport is short', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      host(
        height: 200,
        children: <Widget>[
          const SizedBox(height: 100, child: Text('A')),
          const SizedBox(height: 300, child: Text('B')),
        ],
      ),
    );

    // Nothing throws, and the clipped content is reachable by scrolling -
    // exactly what the login/OTP forms need when the keyboard is open.
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(
      find.text('B'),
      100,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('B'), findsOneWidget);
  });
}
