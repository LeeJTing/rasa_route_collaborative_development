import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rasa_route_collaborative_development/app/theme/app_theme.dart';
import 'package:rasa_route_collaborative_development/domain_model/local_food.dart';
import 'package:rasa_route_collaborative_development/view_models/food_recognition_view_model.dart';
import 'package:rasa_route_collaborative_development/views/add_landmark_view/add_landmark_view.dart';

/// The recognised dish the form opens with when a price test needs the
/// primary price field on screen.
LocalFood _food() => const LocalFood(
  id: 0,
  name: 'Cendol',
  description: 'Shaved ice dessert',
  origin: 'Malaysia',
  culturalBackground: '',
  ingredients: '',
  category: 'Malay',
  cookingStyle: 'Chilling',
  mealType: 'Dessert',
  foodType: 'Food',
);

/// A real 1x1 PNG (junk bytes would only exercise the decode error path).
final Uint8List _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAE'
  'hQGAhKmMIQAAAABJRU5ErkJggg==',
);

XFile _image() =>
    XFile.fromData(_pngBytes, mimeType: 'image/png', name: 'capture.png');

/// The primary food's price field - the only one while no additional food
/// exists. Both price fields now share the 'Price (MYR)' label (the form's
/// standard frame: label above the box), so the hint identifies the input.
Finder _priceField() => find.byWidgetPredicate(
  (Widget widget) =>
      widget is TextField && widget.decoration?.hintText == '0.00',
);

/// The ViewModel's phone error line (see `AddLandmarkViewModel`).
const String _phoneErrorText =
    'Enter a valid Malaysian mobile or landline, e.g. 012-345 6789.';

String _priceText(WidgetTester tester) =>
    tester.widget<TextField>(_priceField()).controller!.text;

/// Renders the whole Add-Landmark form (UC500) with a tall test surface.
///
/// No GPS fix arrives in a widget test, so the map card shows its waiting
/// state and nothing reaches OpenStreetMap (the ViewModel only geocodes while
/// a screen watches AND a location is known).
void main() {
  testWidgets('leads with Location (GPS) and puts the address directly '
      'under it', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    addTearDown(LandmarkDraftHandoff().clear);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const AddLandmarkView()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Add New Landmark'), findsOneWidget);
    expect(find.text('Location (GPS)'), findsOneWidget);
    expect(find.text('Locating...'), findsOneWidget);
    expect(find.text('Restaurant Address (Optional)'), findsOneWidget);

    // The flip: Location (GPS) sits ABOVE the restaurant address, so the spot
    // is picked first and the address follows the pin.
    final double locationY = tester.getTopLeft(find.text('Location (GPS)')).dy;
    final double addressY = tester
        .getTopLeft(find.text('Restaurant Address (Optional)'))
        .dy;
    expect(locationY, lessThan(addressY));

    // Nothing to recover to until the pin has actually been moved.
    expect(find.text('Recover to captured location'), findsNothing);
  });

  testWidgets('price field rewrites leading zeros, blocks words, and formats '
      'to 2 decimals on leave', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    addTearDown(LandmarkDraftHandoff().clear);

    // A recognised food puts the primary price field on the form. No capture
    // location is set on purpose: the address lookup must stay silent.
    LandmarkDraftHandoff().pendingRecognizedFood = _food();

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const AddLandmarkView()),
    );
    await tester.pumpAndSettle();

    final Finder field = _priceField();
    expect(field, findsOneWidget);

    // "01" is rewritten on the spot - a price can never start with 0.
    await tester.enterText(field, '01');
    await tester.pump();
    expect(_priceText(tester), '1.00');

    await tester.enterText(field, '0010.00');
    await tester.pump();
    expect(_priceText(tester), '10.00');

    // The lone 0 of a "0.xx" entry is not a leading zero - it survives.
    await tester.enterText(field, '0.50');
    await tester.pump();
    expect(_priceText(tester), '0.50');

    // Words - English or Chinese - never enter the field.
    await tester.enterText(field, 'abc');
    await tester.pump();
    expect(_priceText(tester), '0.50');
    await tester.enterText(field, '十元');
    await tester.pump();
    expect(_priceText(tester), '0.50');
    await tester.enterText(field, '12.3.4');
    await tester.pump();
    expect(_priceText(tester), '0.50');

    // A plain value stays as typed while the field is focused...
    await tester.enterText(field, '1.5');
    await tester.pump();
    expect(_priceText(tester), '1.5');

    // ...and shows exactly two decimals once the field is left.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(_priceText(tester), '1.50');
  });

  testWidgets('the price box keeps its fixed RM mark, empty and unfocused '
      'included', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    addTearDown(LandmarkDraftHandoff().clear);

    LandmarkDraftHandoff().pendingRecognizedFood = _food();

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const AddLandmarkView()),
    );
    await tester.pumpAndSettle();

    // Untouched and unfocused: only the "0.00" hint shows, and the mark is
    // STILL there beside it. It used to be an `InputDecoration` prefix, which
    // Flutter hides while a field is empty and not focused - the mark came
    // and went with focus.
    expect(_priceText(tester), '');
    expect(find.text('RM'), findsOneWidget);

    // Focusing without typing must not change that...
    await tester.tap(_priceField());
    await tester.pump();
    expect(find.text('RM'), findsOneWidget);

    // ...and neither must a value (which is what used to bring it back).
    await tester.enterText(_priceField(), '12');
    await tester.pump();
    expect(find.text('RM'), findsOneWidget);

    // Leaving it again keeps it, with the value still two-decimal formatted.
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    expect(find.text('RM'), findsOneWidget);
    expect(_priceText(tester), '12.00');
  });

  testWidgets(
    'the phone field shows a fixed +60 and accepts digits only (no words)',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 5000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      addTearDown(LandmarkDraftHandoff().clear);

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const AddLandmarkView()),
      );
      await tester.pumpAndSettle();

      // The prefix is on screen before anything is typed - it is plain text
      // in the field's box (see `_FormTextField.leadingText`), not editable.
      expect(find.text('+60'), findsOneWidget);

      final Finder phoneField = find.byWidgetPredicate(
        (Widget widget) =>
            widget is TextField && widget.decoration?.hintText == '123456789',
      );
      expect(phoneField, findsOneWidget);

      String phoneText() =>
          tester.widget<TextField>(phoneField).controller!.text;

      // Only digits survive - separators are dropped as they arrive...
      await tester.enterText(phoneField, '12-345 6789');
      await tester.pump();
      expect(phoneText(), '123456789');
      expect(find.text(_phoneErrorText), findsNothing);

      // ...and a pasted national number is cleaned the same way (the stored
      // value carries the fixed "+60").
      await tester.enterText(phoneField, '012-345 6789');
      await tester.pump();
      expect(phoneText(), '0123456789');
      expect(find.text(_phoneErrorText), findsNothing);

      // Words never enter the field: a mixed paste keeps only its digits...
      await tester.enterText(phoneField, 'abc12def34');
      await tester.pump();
      expect(phoneText(), '1234');
      expect(find.text(_phoneErrorText), findsOneWidget);

      // ...and a word-only entry leaves the field empty (no error at all).
      await tester.enterText(phoneField, 'abc');
      await tester.pump();
      expect(phoneText(), '');
      expect(find.text(_phoneErrorText), findsNothing);

      // The fixed prefix is untouched by all of that.
      expect(find.text('+60'), findsOneWidget);
    },
  );

  testWidgets('the captured food photo opens full-screen from the form', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 5000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    addTearDown(LandmarkDraftHandoff().clear);

    // The capture screen hands the recognised food (and its photo) over.
    LandmarkDraftHandoff().pendingRecognizedFood = _food();
    LandmarkDraftHandoff().pendingCapturedImage = _image();

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const AddLandmarkView()),
    );
    await tester.pumpAndSettle();

    // The card's thumbnail is a square crop; the "View photo" hint under it
    // is both the guide and part of the tap target - either opens the whole
    // shot, zoomable (see `showEnlargedImage`).
    expect(find.text('View photo'), findsOneWidget);

    await tester.tap(find.text('View photo'));
    await tester.pumpAndSettle();

    expect(find.byType(InteractiveViewer), findsOneWidget);

    await tester.tap(find.byTooltip('Close image'));
    await tester.pumpAndSettle();

    expect(find.byType(InteractiveViewer), findsNothing);
    expect(find.text('View photo'), findsOneWidget);
  });
}
