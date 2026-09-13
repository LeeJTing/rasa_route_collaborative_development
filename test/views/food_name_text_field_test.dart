import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/views/food_recognition_view/widgets/food_name_text_field.dart';

/// The manual food-name input behind "Wrong dish? Type the name" / "Show
/// this food": letters, digits and spaces only - no special characters
/// (user request, 2026-09-14) - in any script.
void main() {
  Future<TextEditingController> pumpField(WidgetTester tester) async {
    final TextEditingController controller = TextEditingController();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FoodNameTextField(
            controller: controller,
            enabled: true,
            maxLength: 50,
            warningFor: (String name) => null,
            onSubmitted: () {},
          ),
        ),
      ),
    );
    return controller;
  }

  testWidgets('special characters are blocked as they are typed', (
    WidgetTester tester,
  ) async {
    final TextEditingController controller = await pumpField(tester);

    await tester.enterText(find.byType(TextField), 'Nasi Goreng!!!');
    expect(controller.text, 'Nasi Goreng');

    await tester.enterText(find.byType(TextField), 'Roti@Canai#2.5');
    expect(controller.text, 'RotiCanai25');

    await tester.enterText(find.byType(TextField), 'Murtabak (besar)');
    expect(controller.text, 'Murtabak besar');

    // Emoji are dropped whole (surrogate pairs never match).
    await tester.enterText(find.byType(TextField), 'Cendol \u{1F367}');
    expect(controller.text, 'Cendol ');
  });

  testWidgets('letters, digits and spaces survive - in any script', (
    WidgetTester tester,
  ) async {
    final TextEditingController controller = await pumpField(tester);

    await tester.enterText(find.byType(TextField), 'Roti 2 Keping');
    expect(controller.text, 'Roti 2 Keping');

    await tester.enterText(find.byType(TextField), '炒粿条');
    expect(controller.text, '炒粿条');
  });
}
