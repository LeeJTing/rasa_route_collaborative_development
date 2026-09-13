import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rasa_route_collaborative_development/domain_model/local_food.dart';
import 'package:rasa_route_collaborative_development/views/common_widgets/recognised_food_card.dart';

/// A real 1x1 PNG (junk bytes would only exercise the decode error path).
final Uint8List _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAE'
  'hQGAhKmMIQAAAABJRU5ErkJggg==',
);

XFile _image() =>
    XFile.fromData(_pngBytes, mimeType: 'image/png', name: 'capture.png');

/// Identifies the card's photo thumbnail - tapping it is how the whole photo
/// is opened (see `RecognisedFoodCard.onImageTap`).
const ValueKey<String> _photoKey = ValueKey<String>('recognised-food-photo');

LocalFood _food({String ingredients = ''}) => LocalFood(
  id: 375,
  name: 'Cendol',
  description: 'A chilled dessert',
  origin: 'Malaysia',
  culturalBackground: '',
  ingredients: ingredients,
  category: 'Nyonya',
  cookingStyle: 'Chilling',
  mealType: 'Dessert',
  foodType: 'Dessert',
);

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('View Details shows the dish ingredients when it has any', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        RecognisedFoodCard(
          food: _food(
            ingredients:
                'Pandan jelly, coconut milk, palm sugar, shaved ice, '
                'gula Melaka, sweet corn',
          ),
          variant: 'Cendol Jagung',
          collapsible: false,
        ),
      ),
    );

    // The dictionary's ingredients plus the variant's addition - the whole
    // point of the inherit-and-merge rule on `landmark_item.ingredients`.
    expect(find.text('Ingredients'), findsOneWidget);
    expect(find.textContaining('sweet corn'), findsOneWidget);
    expect(find.textContaining('Pandan jelly'), findsOneWidget);
  });

  testWidgets('the Ingredients row is hidden when the dish has none', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(RecognisedFoodCard(food: _food(), collapsible: false)),
    );

    expect(find.text('Ingredients'), findsNothing);
  });

  testWidgets('Dish, Variant and Origin values share one aligned column', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        RecognisedFoodCard(
          food: _food(),
          variant: 'Cendol Jagung',
          collapsible: false,
        ),
      ),
    );

    final double dishX = tester.getTopLeft(find.text('Cendol')).dx;
    final double variantX = tester.getTopLeft(find.text('Cendol Jagung')).dx;
    final double originX = tester.getTopLeft(find.text('Malaysia')).dx;

    // One value column for every row - previously the value started right
    // after the label text ("Dish" vs "Variant" vs "Origin" shifted it).
    expect(variantX, dishX);
    expect(originX, dishX);
  });

  testWidgets('on the form card it sits behind the expand arrow', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        RecognisedFoodCard(
          food: _food(ingredients: 'Pandan jelly, sweet corn'),
          collapsible: true,
        ),
      ),
    );

    expect(find.text('Ingredients'), findsNothing);

    await tester.tap(find.byIcon(Icons.expand_more));
    await tester.pumpAndSettle();

    expect(find.text('Ingredients'), findsOneWidget);
  });

  testWidgets('tapping the captured photo opens it when the screen offers it', (
    tester,
  ) async {
    int taps = 0;
    await tester.pumpWidget(
      _wrap(
        RecognisedFoodCard(
          food: _food(),
          image: _image(),
          collapsible: false,
          onImageTap: () => taps++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The card hints at it - the crop on the card is not the whole shot.
    expect(find.text('View photo'), findsOneWidget);

    // Only a square crop fits on the card - the tap is how the tourist gets
    // to the whole shot (the screen shows it full-screen).
    await tester.tap(find.byKey(_photoKey));
    expect(taps, 1);

    // The hint is part of the same target, not decoration.
    await tester.tap(find.text('View photo'));
    expect(taps, 2);
  });

  testWidgets('without a handler the photo stays a plain thumbnail', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(
        RecognisedFoodCard(food: _food(), image: _image(), collapsible: false),
      ),
    );
    await tester.pumpAndSettle();

    // The form card has its own photo controls - nothing here is tappable.
    expect(find.byType(InkWell), findsNothing);
    expect(find.text('View photo'), findsNothing);
  });
}
