import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rasa_route_collaborative_development/domain_model/landmark_draft.dart';
import 'package:rasa_route_collaborative_development/domain_model/local_food.dart';
import 'package:rasa_route_collaborative_development/domain_model/opening_hour.dart';
import 'package:rasa_route_collaborative_development/domain_model/tourist_location.dart';
import 'package:rasa_route_collaborative_development/view_models/add_landmark_view_model.dart';

LocalFood _food(String name, {String category = 'Malay'}) => LocalFood(
  id: 0,
  name: name,
  description: 'Description of $name',
  origin: 'Malaysia',
  culturalBackground: '',
  ingredients: '',
  category: category,
  cookingStyle: 'Frying',
  mealType: 'Breakfast',
  foodType: 'Food',
);

XFile _image() => XFile.fromData(
  Uint8List.fromList(<int>[1, 2, 3]),
  mimeType: 'image/jpeg',
  name: 'test.jpg',
);

const TouristLocation _kl = TouristLocation(
  latitude: 3.1390,
  longitude: 101.6869,
);

LandmarkDraft _draft() => LandmarkDraft(
  id: 42,
  restaurantName: 'Kopitiam Ali',
  phone: '+60 12-345 6789',
  address: '12 Jalan Makan',
  category: 'Malay',
  baseLocation: _kl,
  landmarkPhoto: const LandmarkDraftPhoto(
    id: 'photo/signboard.jpg',
    url: 'https://cdn.example.com/signboard.jpg',
    type: 'signboard',
  ),
  foods: <LandmarkDraftFood>[
    const LandmarkDraftFood(
      food: LocalFood(
        id: 0,
        name: 'Nasi Lemak',
        description: '',
        origin: '',
        culturalBackground: '',
        ingredients: '',
        category: 'Malay',
        cookingStyle: '',
        mealType: '',
        foodType: 'Food',
      ),
      price: 6.5,
      priceMin: 5,
      priceMax: 8,
      confidence: 0.9,
      dietaryRestrictions: <String>['No Pork'],
      captureLocation: _kl,
      photo: LandmarkDraftPhoto(
        id: 'photo/food-a.jpg',
        url: 'https://cdn.example.com/food-a.jpg',
      ),
    ),
    LandmarkDraftFood(
      food: _food('Teh Tarik', category: 'Beverage'),
      price: 2.5,
      captureLocation: _kl,
    ),
  ],
  operatingHours: <Weekday, List<OpeningHour>>{
    Weekday.monday: <OpeningHour>[
      const OpeningHour(
        id: 0,
        day: Weekday.monday,
        status: DayStatus.open,
        opensAt: 9 * 60,
        closesAt: 17 * 60,
      ),
    ],
  },
  expiresAt: DateTime.now().add(const Duration(hours: 24)),
  updatedAt: DateTime.now(),
);

/// A form that satisfies every submit requirement EXCEPT the operating
/// hours, so the hours rules are the only thing a failure can come from.
/// Includes the Confirm step, which submission is gated on.
///
/// [websiteReachability] is the website-link probe seam (see
/// `AddLandmarkViewModel.websiteReachability`), for the tests that make the
/// live link check fail on purpose.
Future<AddLandmarkViewModel> _readyToSubmit({
  Future<bool> Function(String url)? websiteReachability,
}) async {
  final AddLandmarkViewModel vm = AddLandmarkViewModel(
    websiteReachability: websiteReachability,
  );
  await vm.onInit();
  vm.setRecognizedFood(_food('Nasi Lemak'), captureLocation: _kl);
  vm.setPrimaryFoodPrice(6.5);
  vm.setRestaurantName('Kopitiam Ali');
  vm.setCapturedImage(_image(), 'signboard');
  // Awaited: Confirm now does its similar-place search, so the confirmation
  // only lands once that returns.
  await vm.confirmRestaurant();
  return vm;
}

void main() {
  group('AddLandmarkViewModel restoreDraft', () {
    test('restores every field the tourist had entered', () async {
      final AddLandmarkViewModel vm = AddLandmarkViewModel();
      await vm.onInit();

      vm.restoreDraft(_draft());

      expect(vm.draftId, 42);
      // Resumed from a saved incomplete submission - so its Discard lives on
      // the Incomplete Submissions screen, not in the leave dialog.
      expect(vm.hasSavedDraft, isTrue);
      expect(vm.restaurantName, 'Kopitiam Ali');
      expect(vm.restaurantPhone, '012-345 6789');
      expect(vm.restaurantAddress, '12 Jalan Makan');
      expect(vm.captureLocation.latitude, closeTo(3.1390, 0.00001));
      expect(vm.baseLocation.latitude, closeTo(3.1390, 0.00001));
      expect(vm.hasImageCaptured, isTrue);
      expect(vm.capturedImage, isNull); // lives in storage now
      expect(vm.capturedImageUrl, 'https://cdn.example.com/signboard.jpg');
      expect(vm.capturedImageType, 'signboard');
      expect(vm.isStallDisabled, isTrue);

      expect(vm.recognizedFood?.name, 'Nasi Lemak');
      expect(vm.primaryFoodPrice, 6.5);
      expect(vm.recognizedFoodImageUrl, 'https://cdn.example.com/food-a.jpg');
      expect(vm.additionalFoods.length, 1);
      expect(vm.additionalFoods.single.food.name, 'Teh Tarik');
      expect(vm.additionalFoods.single.price, 2.5);
      expect(vm.additionalFoods.single.photoRef, isNull);

      final List<OpeningHour> monday = vm.operatingHours[Weekday.monday]!;
      expect(monday.length, 1);
      expect(monday.single.opensAt, 9 * 60);
      expect(monday.single.closesAt, 17 * 60);

      vm.dispose();
    });

    test('restores a hand-moved pin as the adjusted location', () async {
      final AddLandmarkViewModel vm = AddLandmarkViewModel();
      await vm.onInit();

      vm.restoreDraft(_draft());
      // A pinned-correction location from the draft, ~30 m from the fix.
      vm.adjustLandmarkLocation(3.1393, 101.6869);

      expect(vm.adjustedLocation.isKnown, isTrue);
      expect(vm.adjustedLocation.latitude, closeTo(3.1393, 0.00001));

      vm.dispose();
    });

    test('a fresh form is not editing a saved submission', () async {
      final AddLandmarkViewModel vm = AddLandmarkViewModel();
      await vm.onInit();

      expect(vm.hasSavedDraft, isFalse);
      vm.dispose();
    });
  });

  group('AddLandmarkViewModel draft content', () {
    test('a fresh form has nothing worth saving', () async {
      final AddLandmarkViewModel vm = AddLandmarkViewModel();
      await vm.onInit();
      expect(vm.hasDraftContent, isFalse);
      vm.dispose();
    });

    test('a form with a recognized food has content', () async {
      final AddLandmarkViewModel vm = AddLandmarkViewModel();
      await vm.onInit();
      vm.setRecognizedFood(_food('Nasi Lemak'), captureLocation: _kl);
      expect(vm.hasDraftContent, isTrue);
      vm.dispose();
    });
  });

  group('AddLandmarkViewModel draft persistence (no signed-in tourist)', () {
    test('saveDraft reports nothing was written instead of throwing', () async {
      final AddLandmarkViewModel vm = await _readyToSubmit();

      final bool saved = await vm.saveDraft();

      // No Supabase session in a unit test - the draft is not written, and
      // no user-facing error is raised (a background save stays silent).
      expect(saved, isFalse);
      expect(vm.draftId, 0);

      vm.dispose();
    });

    test('discardDraft is safe when nothing was ever saved', () async {
      final AddLandmarkViewModel vm = await _readyToSubmit();

      await vm.discardDraft();

      expect(vm.draftId, 0);
      vm.dispose();
    });
  });

  group(
    'operating hours gate the form (req: 1 hour minimum, no linked rows)',
    () {
      test(
        'linked rows (09:00-12:00 + 12:00-14:00) block submission',
        () async {
          final AddLandmarkViewModel vm = await _readyToSubmit();
          vm.setDayStatus(Weekday.monday, DayStatus.open);
          vm.addTimeRange(Weekday.monday);
          vm.setRangeTime(Weekday.monday, 0, true, 9 * 60);
          vm.setRangeTime(Weekday.monday, 0, false, 12 * 60);
          vm.setRangeTime(Weekday.monday, 1, true, 12 * 60);
          vm.setRangeTime(Weekday.monday, 1, false, 14 * 60);

          expect(vm.canSubmit, isFalse);
          expect(vm.canSubmitReason, contains('continuous'));

          vm.dispose();
        },
      );

      test('a row shorter than an hour blocks submission', () async {
        final AddLandmarkViewModel vm = await _readyToSubmit();
        vm.setDayStatus(Weekday.monday, DayStatus.open);
        vm.setRangeTime(Weekday.monday, 0, true, 9 * 60);
        vm.setRangeTime(Weekday.monday, 0, false, 9 * 60 + 30);

        expect(vm.canSubmit, isFalse);
        expect(vm.canSubmitReason, contains('shorter than 1 hour'));

        vm.dispose();
      });

      test('valid hours let the form submit', () async {
        final AddLandmarkViewModel vm = await _readyToSubmit();
        vm.setDayStatus(Weekday.monday, DayStatus.open);
        vm.setRangeTime(Weekday.monday, 0, true, 9 * 60);
        vm.setRangeTime(Weekday.monday, 0, false, 17 * 60);

        expect(vm.canSubmitReason, isNull);
        expect(vm.canSubmit, isTrue);

        vm.dispose();
      });
    },
  );

  group('the live website-link probe gates Submit', () {
    test(
      'an unverified or unopenable link disables Submit and says why',
      () async {
        final AddLandmarkViewModel vm = await _readyToSubmit(
          websiteReachability: (String url) async =>
              url == 'https://works.example',
        );
        // The form is on screen, so the debounced probe may run at all.
        vm.addListener(() {});
        vm.setDayStatus(Weekday.monday, DayStatus.open);
        vm.setRangeTime(Weekday.monday, 0, true, 9 * 60);
        vm.setRangeTime(Weekday.monday, 0, false, 17 * 60);
        vm.setRestaurantWebsite('https://gone.example');

        // UNVERIFIED while the debounce/probe is pending: the field is
        // editable but Submit waits for the check (user report, 2026-09-14 -
        // the button used to be clickable here).
        expect(vm.isWebsiteLinkSettling, isTrue);
        expect(vm.canSubmit, isFalse);
        expect(vm.canSubmitReason, 'Checking this link…');

        await Future<void>.delayed(
          AddLandmarkViewModel.websiteLinkCheckDelay +
              const Duration(milliseconds: 100),
        );
        expect(vm.websiteLinkUnreachable, isTrue);
        expect(vm.isWebsiteLinkSettling, isFalse);
        expect(vm.canSubmit, isFalse);
        expect(
          vm.canSubmitReason,
          "We couldn't open this website. Check the address and try again.",
        );

        // Editing the field re-probes: still settling until the new probe
        // answers, then a link that works unblocks Submit.
        vm.setRestaurantWebsite('https://works.example');
        expect(vm.canSubmit, isFalse);
        await Future<void>.delayed(
          AddLandmarkViewModel.websiteLinkCheckDelay +
              const Duration(milliseconds: 100),
        );
        expect(vm.websiteLinkUnreachable, isFalse);
        expect(vm.isWebsiteLinkSettling, isFalse);
        expect(vm.canSubmitReason, isNull);
        expect(vm.canSubmit, isTrue);

        vm.dispose();
      },
    );
  });
}
