import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:rasa_route_collaborative_development/main.dart' as app;

/// Full-app integration tests (Flutter's device testing tool).
///
/// These run the REAL app on a real device/emulator - `flutter test
/// integration_test` - so they exercise the actual entry point
/// ([app.main]: Env.load -> SupabaseService.initialise -> runApp ->
/// LocationMonitor), the real route table, theme and the live camera screen.
///
/// Scope note: this suite deliberately stays a launch/UI smoke test rather
/// than trying to drive the full camera -> Gemini -> submit flow. The in-app
/// camera is a live native feed and Gemini is a paid live API, so that path
/// can't be automated reliably here; it is covered by the hermetic unit tests
/// in `test/` and by manual device testing. This suite's job is to prove the
/// real app boots and renders correctly on hardware.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app boots into the Add New Landmark (food recognition) screen', (
    tester,
  ) async {
    // Run the real entry point exactly as the installed app would.
    await app.main();

    // Render the first frames. Deliberately NOT pumpAndSettle: the camera
    // viewfinder shows an indeterminate spinner while it initialises (an
    // infinite animation that never "settles") and a live CameraPreview keeps
    // scheduling frames - so settle would hang or time out. Explicit pumps
    // are the stable way to bring the first real frame up.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 800));

    // The app bar title is the same for every capture purpose (food /
    // additional food / signboard / stall) - the screen is always under the
    // "Add New Landmark" journey.
    expect(find.text('Add New Landmark'), findsOneWidget);

    // The shutter button is always present, whether or not the camera
    // finished initialising (it just dims when not ready yet).
    expect(find.byIcon(Icons.camera_alt), findsOneWidget);
  });
}
