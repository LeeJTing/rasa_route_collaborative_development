import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/view_models/add_landmark_view_model.dart';

void main() {
  group('AddLandmarkViewModel restaurant name (signboard overwrite, UC500)', () {
    test('signboard extraction overwrites a previously typed name', () {
      final AddLandmarkViewModel vm = AddLandmarkViewModel();
      vm.setRestaurantName('Tourist Typed Cafe');
      expect(vm.restaurantName, 'Tourist Typed Cafe');

      // A signboard capture result must replace the typed name - the
      // signboard is authoritative, and the tourist can edit it afterwards.
      vm.setExtractedRestaurantName('Signboard Kopitiam');
      expect(vm.restaurantName, 'Signboard Kopitiam');
      vm.dispose();
    });

    test('extraction version bumps only on a real signboard extraction', () {
      final AddLandmarkViewModel vm = AddLandmarkViewModel();
      final int initial = vm.extractedRestaurantNameVersion;

      // The tourist's own typing must never bump the extraction version,
      // otherwise the View could not tell typing apart from a signboard result.
      vm.setRestaurantName('Typed Name');
      expect(
        vm.extractedRestaurantNameVersion,
        initial,
        reason: 'typing must not bump the extraction version',
      );

      vm.setExtractedRestaurantName('Extracted Name');
      expect(vm.extractedRestaurantNameVersion, initial + 1);

      // Null/empty/whitespace extractions are ignored and do not bump.
      vm.setExtractedRestaurantName(null);
      vm.setExtractedRestaurantName('');
      vm.setExtractedRestaurantName('   ');
      expect(vm.extractedRestaurantNameVersion, initial + 1);
      vm.dispose();
    });

    test('extraction overwrites again even after the user edits later', () {
      final AddLandmarkViewModel vm = AddLandmarkViewModel();
      vm.setRestaurantName('First');
      vm.setExtractedRestaurantName('Signboard');
      vm.setRestaurantName('Edited After Signboard');
      expect(vm.restaurantName, 'Edited After Signboard');

      // Retaking the signboard produces a new extraction - it overwrites
      // whatever is in the field and bumps the version again.
      vm.setExtractedRestaurantName('New Signboard');
      expect(vm.restaurantName, 'New Signboard');
      expect(vm.extractedRestaurantNameVersion, 2);
      vm.dispose();
    });

    test('extracted name is trimmed before it is stored', () {
      final AddLandmarkViewModel vm = AddLandmarkViewModel();
      vm.setExtractedRestaurantName('  Nasi Lemak House  \n');
      expect(vm.restaurantName, 'Nasi Lemak House');
      vm.dispose();
    });

    test('a shouted signboard reading is stored in readable casing', () {
      final AddLandmarkViewModel vm = AddLandmarkViewModel();

      // Gemini transcribes a sign AS LETTERED, so the same shop came back as
      // "Restoran X" or "RESTORAN X" depending on its signboard - the field
      // (and therefore the saved landmark) keeps one readable spelling
      // instead of looking like two different places.
      vm.setExtractedRestaurantName('RESTORAN JELAPANG');
      expect(vm.restaurantName, 'Restoran Jelapang');

      // A mixed-case name is the name's own casing - never reshaped.
      vm.setExtractedRestaurantName('myBurgerLab');
      expect(vm.restaurantName, 'myBurgerLab');
      vm.dispose();
    });
  });
}
