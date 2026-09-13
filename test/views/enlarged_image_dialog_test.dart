import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rasa_route_collaborative_development/app/theme/app_theme.dart';
import 'package:rasa_route_collaborative_development/views/common_widgets/enlarged_image_dialog.dart';

/// A real 1x1 PNG, so the test decodes actual image data instead of only
/// exercising the error path.
final Uint8List _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAE'
  'hQGAhKmMIQAAAABJRU5ErkJggg==',
);

XFile _image() =>
    XFile.fromData(_pngBytes, mimeType: 'image/png', name: 'capture.png');

void main() {
  testWidgets('a captured photo opens full-screen and closes again', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: Builder(
            builder: (BuildContext context) => Center(
              child: ElevatedButton(
                onPressed: () => showEnlargedImage(
                  context,
                  file: _image(),
                  semanticLabel: 'Captured photo of Cendol',
                ),
                child: const Text('Open photo'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open photo'));
    await tester.pumpAndSettle();

    // The WHOLE photo over the dark scrim, pinch/drag zoomable - the same
    // overlay the food-detail and submitted-landmark screens show.
    expect(find.byType(InteractiveViewer), findsOneWidget);
    expect(
      tester.widget<InteractiveViewer>(find.byType(InteractiveViewer)).maxScale,
      greaterThan(1),
    );
    expect(
      tester.widget<Image>(find.byType(Image)).semanticLabel,
      'Captured photo of Cendol',
    );

    await tester.tap(find.byTooltip('Close image'));
    await tester.pumpAndSettle();

    expect(find.byType(InteractiveViewer), findsNothing);
    expect(find.byType(Image), findsNothing);
  });
}
