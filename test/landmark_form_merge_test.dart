import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rasa_route_collaborative_development/domain_model/landmark_draft.dart';
import 'package:rasa_route_collaborative_development/domain_model/local_food.dart';
import 'package:rasa_route_collaborative_development/domain_model/opening_hour.dart';
import 'package:rasa_route_collaborative_development/domain_model/tourist_location.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/landmark_logic_facade.dart';
import 'package:rasa_route_collaborative_development/view_models/add_landmark_view_model.dart';

LocalFood _food(String name) => LocalFood(
  id: 0,
  name: name,
  description: 'Description of $name',
  origin: 'Malaysia',
  culturalBackground: '',
  ingredients: '',
  category: 'Malay',
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

/// The facade seam: the drafts the form's Confirm action reads and the two
/// writes a draft save makes. Everything else (identity rules, labels, the
/// restaurant match) stays the real logic.
class _FakeLandmarkLogicFacade extends LandmarkLogicFacade {
  List<LandmarkDraft> drafts = const <LandmarkDraft>[];

  /// The rows removed after a save (see
  /// `AddLandmarkViewModel.mergeExistingDraft`).
  final List<int> clearedDraftIds = <int>[];

  /// The row id reported for a NEW draft.
  int nextDraftId = 7;

  @override
  Future<List<LandmarkDraft>> pendingLandmarkDrafts() async => drafts;

  @override
  Future<int> saveLandmarkDraft(LandmarkDraft draft) async =>
      // An update keeps its row; a new draft gets a fresh id.
      draft.id == 0 ? nextDraftId : draft.id;

  @override
  Future<void> clearSubmittedLandmarkDraft(int draftId) async {
    clearedDraftIds.add(draftId);
  }

  @override
  Future<({String id, String url})> uploadImage(List<int> bytes) async =>
      (id: 'photo/upload.jpg', url: 'https://cdn.example.com/upload.jpg');
}

class _TestAddLandmarkViewModel extends AddLandmarkViewModel {
  _TestAddLandmarkViewModel(this.facade);

  final _FakeLandmarkLogicFacade facade;

  @override
  LandmarkLogicFacade createLandmarkLogic() => facade;
}

/// A form with a food, a price, a name and the mandatory signboard photo -
/// everything submission needs except the Confirm click.
Future<_TestAddLandmarkViewModel> _form({
  String name = 'Tian Yi',
  String variant = 'Cendol Jagung',
  _FakeLandmarkLogicFacade? facade,
}) async {
  final _TestAddLandmarkViewModel vm = _TestAddLandmarkViewModel(
    facade ?? _FakeLandmarkLogicFacade(),
  );
  await vm.onInit();
  vm.setRecognizedFood(_food('Cendol'), variant: variant, captureLocation: _kl);
  vm.setPrimaryFoodPrice(3.0);
  vm.setRestaurantName(name);
  vm.setCapturedImage(_image(), 'signboard');
  return vm;
}

/// This form's OWN saved submission, as restored from the Incomplete
/// Submissions list: the same restaurant, already confirmed, with the
/// signboard photo and its own fix.
LandmarkDraft _ownDraft() => LandmarkDraft(
  id: 9,
  restaurantName: 'Tian Yi',
  baseLocation: _kl,
  restaurantConfirmed: true,
  landmarkPhoto: const LandmarkDraftPhoto(
    id: 'photo/signboard.jpg',
    url: 'https://cdn.example.com/signboard.jpg',
    type: 'signboard',
    captureLocation: TouristLocation(latitude: 3.1388, longitude: 101.6867),
  ),
  foods: <LandmarkDraftFood>[
    LandmarkDraftFood(
      food: _food('Cendol'),
      variant: 'Cendol Jagung',
      price: 3.0,
      captureLocation: _kl,
    ),
  ],
  expiresAt: DateTime.now().add(const Duration(hours: 24)),
  updatedAt: DateTime.now(),
);

/// The saved submission: same restaurant, one dish this form already holds
/// (with its own price + a photo), two dishes it does not, contact details
/// and Tuesday hours this form has not entered.
LandmarkDraft _savedDraft() => LandmarkDraft(
  id: 42,
  restaurantName: 'Tian Yi',
  phone: '+60 12-345 6789',
  address: '12 Jalan Makan',
  baseLocation: _kl,
  foods: <LandmarkDraftFood>[
    LandmarkDraftFood(
      food: _food('Cendol'),
      variant: 'Cendol Jagung',
      price: 5.0,
      captureLocation: _kl,
      photo: const LandmarkDraftPhoto(
        id: 'photo/food-a.jpg',
        url: 'https://cdn.example.com/food-a.jpg',
      ),
    ),
    LandmarkDraftFood(
      food: _food('Teh Tarik'),
      price: 2.5,
      captureLocation: _kl,
    ),
    LandmarkDraftFood(food: _food('Nasi Lemak'), captureLocation: _kl),
  ],
  operatingHours: <Weekday, List<OpeningHour>>{
    Weekday.tuesday: <OpeningHour>[
      const OpeningHour(
        id: 0,
        day: Weekday.tuesday,
        status: DayStatus.open,
        opensAt: 10 * 60,
        closesAt: 16 * 60,
      ),
    ],
  },
  expiresAt: DateTime.now().add(const Duration(hours: 24)),
  updatedAt: DateTime.now(),
);

void main() {
  group('AddLandmarkViewModel restaurant Confirm', () {
    test('needs the signboard/stall photo and a non-blank name', () async {
      final _TestAddLandmarkViewModel vm = _TestAddLandmarkViewModel(
        _FakeLandmarkLogicFacade(),
      );
      await vm.onInit();
      vm.setRecognizedFood(_food('Cendol'), captureLocation: _kl);
      vm.setPrimaryFoodPrice(3.0);

      // No photo yet.
      expect(vm.confirmRestaurant(), contains('signboard or stall'));
      expect(vm.restaurantConfirmed, isFalse);

      // Photo in place, name still blank.
      vm.setCapturedImage(_image(), 'signboard');
      expect(vm.confirmRestaurant(), contains('restaurant name'));
      expect(vm.restaurantConfirmed, isFalse);

      vm.setRestaurantName('Tian Yi');
      expect(vm.confirmRestaurant(), isNull);
      expect(vm.restaurantConfirmed, isTrue);
      vm.dispose();
    });

    test('submission is gated on the Confirm click', () async {
      final _TestAddLandmarkViewModel vm = await _form();

      expect(vm.canSubmit, isFalse);
      expect(vm.canSubmitReason, contains('Confirm'));

      vm.confirmRestaurant();

      expect(vm.canSubmitReason, isNull);
      expect(vm.canSubmit, isTrue);
      vm.dispose();
    });

    test('editing the restaurant name takes the confirmation back', () async {
      final _TestAddLandmarkViewModel vm = await _form();
      vm.confirmRestaurant();
      expect(vm.canSubmit, isTrue);

      vm.setRestaurantName('Tian Yi Seafood');

      // The old click checked the OLD name - it no longer applies.
      expect(vm.restaurantConfirmed, isFalse);
      expect(vm.canSubmit, isFalse);
      expect(vm.canSubmitReason, contains('Confirm'));

      // Confirming the NEW name passes again.
      expect(vm.confirmRestaurant(), isNull);
      expect(vm.canSubmit, isTrue);
      vm.dispose();
    });

    test(
      'the SAME name - only spacing differs - keeps the confirmation',
      () async {
        final _TestAddLandmarkViewModel vm = await _form();
        vm.confirmRestaurant();

        // Re-typing the same name (it trims to the same value) is not a change.
        vm.setRestaurantName('  Tian Yi  ');
        expect(vm.restaurantConfirmed, isTrue);

        // A new signboard reading with the SAME name keeps it too...
        vm.setExtractedRestaurantName('Tian Yi');
        expect(vm.restaurantConfirmed, isTrue);

        // ...but a different one takes it back, like any name change.
        vm.setExtractedRestaurantName('Tian Yi Seafood');
        expect(vm.restaurantConfirmed, isFalse);
        vm.dispose();
      },
    );

    test('finds the saved submission for the same restaurant', () async {
      final _FakeLandmarkLogicFacade facade = _FakeLandmarkLogicFacade()
        ..drafts = <LandmarkDraft>[_savedDraft()];
      final _TestAddLandmarkViewModel vm = await _form(facade: facade);

      vm.confirmRestaurant();
      final LandmarkDraft? found = await vm.draftForRestaurantMerge();

      expect(found?.id, 42);
      vm.dispose();
    });

    test('a saved submission for another restaurant is not offered', () async {
      final _FakeLandmarkLogicFacade facade = _FakeLandmarkLogicFacade()
        ..drafts = <LandmarkDraft>[
          LandmarkDraft(
            id: 43,
            restaurantName: 'Kopitiam Lain',
            baseLocation: _kl,
            foods: <LandmarkDraftFood>[
              LandmarkDraftFood(food: _food('Teh Tarik')),
            ],
            expiresAt: DateTime.now().add(const Duration(hours: 24)),
            updatedAt: DateTime.now(),
          ),
        ];
      final _TestAddLandmarkViewModel vm = await _form(facade: facade);

      vm.confirmRestaurant();

      expect(await vm.draftForRestaurantMerge(), isNull);
      vm.dispose();
    });
  });

  group('AddLandmarkViewModel resumed-draft combining', () {
    test('a resumed draft keeps its confirmed state and photo fix', () async {
      final _TestAddLandmarkViewModel vm = _TestAddLandmarkViewModel(
        _FakeLandmarkLogicFacade(),
      );
      await vm.onInit();

      vm.restoreDraft(_ownDraft());

      // No Confirm click needed on a resumed, already-confirmed form.
      expect(vm.restaurantConfirmed, isTrue);
      expect(vm.capturedImageLocation.latitude, closeTo(3.1388, 0.00001));
      expect(vm.capturedImageLocation.longitude, closeTo(101.6867, 0.00001));
      vm.dispose();
    });

    test(
      'editing the name of a resumed confirmed draft takes it back',
      () async {
        final _TestAddLandmarkViewModel vm = _TestAddLandmarkViewModel(
          _FakeLandmarkLogicFacade(),
        );
        await vm.onInit();
        vm.restoreDraft(_ownDraft());
        expect(vm.restaurantConfirmed, isTrue);

        vm.setRestaurantName('Tian Yi Kopitiam');

        // The restored confirmation checked the saved name - the edit wants
        // its OWN check (and draft lookup) via Confirm.
        expect(vm.restaurantConfirmed, isFalse);
        expect(vm.confirmRestaurant(), isNull);
        expect(vm.restaurantConfirmed, isTrue);
        vm.dispose();
      },
    );

    test(
      'a resumed form combines with ANOTHER draft but keeps its own row',
      () async {
        final _FakeLandmarkLogicFacade facade = _FakeLandmarkLogicFacade()
          ..drafts = <LandmarkDraft>[_ownDraft(), _savedDraft()];
        final _TestAddLandmarkViewModel vm = _TestAddLandmarkViewModel(facade);
        await vm.onInit();
        vm.restoreDraft(_ownDraft());

        // Its own row (9) is skipped - the OTHER submission (42) is offered.
        final LandmarkDraft found = (await vm.draftForRestaurantMerge())!;
        expect(found.id, 42);

        vm.mergeExistingDraft(found);

        // The form keeps ITS row; the other draft's dishes joined as added
        // foods (its "Cendol Jagung" was already the form's own dish).
        expect(vm.draftId, 9);
        expect(
          vm.additionalFoods.map((LandmarkFoodEntry e) => e.food.name).toList(),
          <String>['Teh Tarik', 'Nasi Lemak'],
        );

        // Saving the combined form removes the absorbed row: ONE draft left.
        expect(await vm.saveDraft(), isTrue);
        expect(facade.clearedDraftIds, <int>[42]);
        expect(vm.draftId, 9);
        vm.dispose();
      },
    );
  });

  group('AddLandmarkViewModel.mergeExistingDraft', () {
    test('moves the saved dishes in and keeps this form\'s values', () async {
      final _FakeLandmarkLogicFacade facade = _FakeLandmarkLogicFacade()
        ..drafts = <LandmarkDraft>[_savedDraft()];
      final _TestAddLandmarkViewModel vm = await _form(facade: facade);
      vm.confirmRestaurant();
      final LandmarkDraft saved = (await vm.draftForRestaurantMerge())!;

      final List<String> updated = vm.mergeExistingDraft(saved);

      // The draft's dishes this form did not have joined as added foods; its
      // "Cendol Jagung" was NOT added twice.
      expect(
        vm.additionalFoods
            .map(
              (LandmarkFoodEntry entry) =>
                  entry.variant.isEmpty ? entry.food.name : entry.variant,
            )
            .toList(),
        <String>['Teh Tarik', 'Nasi Lemak'],
      );

      // This form's own price wins; the draft's photo filled the blank one -
      // and that dish is reported so the View can say its details were
      // updated instead of added again.
      expect(vm.primaryFoodPrice, 3.0);
      expect(vm.recognizedFoodImageUrl, 'https://cdn.example.com/food-a.jpg');
      expect(updated, <String>['Cendol Jagung']);

      // Blank contact fields took the draft's.
      expect(vm.restaurantPhone, '+60 12-345 6789');
      expect(vm.restaurantAddress, '12 Jalan Makan');

      // A day this form left empty took the draft's hours.
      final List<OpeningHour> tuesday = vm.operatingHours[Weekday.tuesday]!;
      expect(tuesday.single.opensAt, 10 * 60);
      expect(tuesday.single.closesAt, 16 * 60);

      // This form now UPDATES that submission - no second draft.
      expect(vm.draftId, 42);
      expect(vm.hasSavedDraft, isTrue);
      vm.dispose();
    });

    test('this form\'s filled fields are never overwritten', () async {
      final _FakeLandmarkLogicFacade facade = _FakeLandmarkLogicFacade()
        ..drafts = <LandmarkDraft>[_savedDraft()];
      final _TestAddLandmarkViewModel vm = await _form(facade: facade);
      vm.setRestaurantPhone('+60 19-000 0000');
      vm.setDayStatus(Weekday.tuesday, DayStatus.open);
      vm.setRangeTime(Weekday.tuesday, 0, true, 8 * 60);
      vm.setRangeTime(Weekday.tuesday, 0, false, 14 * 60);
      vm.confirmRestaurant();
      final LandmarkDraft saved = (await vm.draftForRestaurantMerge())!;

      vm.mergeExistingDraft(saved);

      expect(vm.restaurantPhone, '+60 19-000 0000');
      final List<OpeningHour> tuesday = vm.operatingHours[Weekday.tuesday]!;
      expect(tuesday.single.opensAt, 8 * 60);
      expect(tuesday.single.closesAt, 14 * 60);
      vm.dispose();
    });

    test('an additional food already on the form is only filled', () async {
      final _FakeLandmarkLogicFacade facade = _FakeLandmarkLogicFacade()
        ..drafts = <LandmarkDraft>[_savedDraft()];
      final _TestAddLandmarkViewModel vm = await _form(facade: facade);
      // This form already carries the draft's Teh Tarik, without a price.
      vm.addAdditionalFood(_food('Teh Tarik'));
      vm.confirmRestaurant();
      final LandmarkDraft saved = (await vm.draftForRestaurantMerge())!;

      final List<String> updated = vm.mergeExistingDraft(saved);

      // One Teh Tarik, not two - it just took the draft's price; the draft's
      // NEW dish (Nasi Lemak) joined as an added food.
      expect(vm.additionalFoods.map((e) => e.food.name).toList(), <String>[
        'Teh Tarik',
        'Nasi Lemak',
      ]);
      expect(vm.additionalFoods.first.price, 2.5);
      expect(updated, <String>['Cendol Jagung', 'Teh Tarik']);
      vm.dispose();
    });
  });
}
