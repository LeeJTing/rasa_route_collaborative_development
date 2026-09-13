import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rasa_route_collaborative_development/app/theme/app_theme.dart';
import 'package:rasa_route_collaborative_development/domain_model/local_food.dart';
import 'package:rasa_route_collaborative_development/view_models/food_recognition_view_model.dart';
import 'package:rasa_route_collaborative_development/views/landmark_detail_view/landmark_detail_view.dart';

/// The dish the capture screen hands over to "View Details".
LocalFood _food() => const LocalFood(
  id: 375,
  name: 'Cendol',
  description: 'A chilled dessert',
  origin: 'Malaysia',
  culturalBackground: '',
  ingredients: '',
  category: 'Nyonya',
  cookingStyle: 'Chilling',
  mealType: 'Dessert',
  foodType: 'Dessert',
);

/// A real 1x1 PNG (a handful of junk bytes would only exercise the decode
/// error path).
final Uint8List _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAE'
  'hQGAhKmMIQAAAABJRU5ErkJggg==',
);

XFile _capture() =>
    XFile.fromData(_pngBytes, mimeType: 'image/png', name: 'capture.png');

/// Identifies the card's photo thumbnail (`RecognisedFoodCard`).
const ValueKey<String> _photoKey = ValueKey<String>('recognised-food-photo');

void main() {
  testWidgets('the captured photo opens full-screen from View Details', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    addTearDown(LandmarkDraftHandoff().clear);

    // The hand-over the capture popup performs before pushing this screen.
    LandmarkDraftHandoff().pendingRecognizedFood = _food();
    LandmarkDraftHandoff().pendingCapturedImage = _capture();

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const LandmarkDetailView()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cendol'), findsOneWidget);
    expect(find.byKey(_photoKey), findsOneWidget);

    // The card tells the tourist the crop can be opened.
    expect(find.text('View photo'), findsOneWidget);

    // Tapping the thumbnail opens the whole shot, zoomable - the card alone
    // only shows a small square crop of it.
    await tester.tap(find.byKey(_photoKey));
    await tester.pumpAndSettle();

    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is Image &&
            widget.semanticLabel == 'Captured photo of Cendol',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Close image'));
    await tester.pumpAndSettle();

    // Back on the detail screen, photo still there as the thumbnail.
    expect(find.byType(InteractiveViewer), findsNothing);
    expect(find.byKey(_photoKey), findsOneWidget);
  });
}
