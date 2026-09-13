import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rasa_route_collaborative_development/domain_model/address_suggestion.dart';
import 'package:rasa_route_collaborative_development/domain_model/landmark_draft.dart';
import 'package:rasa_route_collaborative_development/domain_model/local_food.dart';
import 'package:rasa_route_collaborative_development/domain_model/opening_hour.dart';
import 'package:rasa_route_collaborative_development/domain_model/place_overwrite_report.dart';
import 'package:rasa_route_collaborative_development/domain_model/similar_place_candidate.dart';
import 'package:rasa_route_collaborative_development/domain_model/stored_place_details.dart';
import 'package:rasa_route_collaborative_development/domain_model/tourist_location.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/landmark_logic_facade.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/landmark_submission_logic.dart';
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

  /// Every (signboard photo, typed name) pair the edited-name check was asked
  /// about - empty when the form never had to ask (see
  /// [signboardNameScore]).
  final List<({List<int> bytes, String typedName})> nameChecks =
      <({List<int> bytes, String typedName})>[];

  /// How the check answers: the similarity score Gemini would return, or
  /// null to make the check itself fail (offline/timeout).
  double? signboardNameScore = 1.0;

  /// The nearby places the near-duplicate check is offered - empty (the
  /// default) means "nothing similar around", so the Confirm click behaves
  /// exactly as it did before that feature.
  List<SimilarPlaceCandidate> similarPlaces = const <SimilarPlaceCandidate>[];

  /// Which photos the photo comparison says are the same place: candidate ids
  /// (see [photoMatches]).
  Set<int> samePlacePhotoIds = <int>{};

  /// The dish names [dishesAlreadyAtPlace] reports - the "already listed at
  /// that place" answer.
  List<String> existingDishNames = const <String>[];

  /// Every candidate id [photosShowSamePlace] was asked about.
  final List<int> photoMatches = <int>[];

  /// Every (typed name, nearby search) call, so a test can prove the search
  /// really ran with the form's own name.
  final List<String> similarPlaceSearches = <String>[];

  @override
  Future<List<SimilarPlaceCandidate>> similarNearbyPlaces({
    required String name,
    required double? latitude,
    required double? longitude,
    double maxMetres = LandmarkSubmissionLogic.similarPlaceRangeMetres,
    int limit = LandmarkSubmissionLogic.similarPlaceCandidateLimit,
  }) async {
    similarPlaceSearches.add(name);
    return similarPlaces;
  }

  @override
  Future<bool> photosShowSamePlace({
    required List<int> imageBytes,
    required SimilarPlaceCandidate candidate,
  }) async {
    photoMatches.add(candidate.id);
    return samePlacePhotoIds.contains(candidate.id);
  }

  @override
  Future<List<String>> dishesAlreadyAtPlace({
    required SimilarPlaceCandidate candidate,
    required List<({String name, String variant, int localFoodId})> dishes,
  }) async => existingDishNames;

  /// What the same-place merge reports as details it would replace - null
  /// (the default) means "nothing to ask about".
  PlaceOverwriteReport? overwriteReport;

  /// Every (name, submitted details) the question was asked with.
  final List<String> overwriteChecks = <String>[];

  @override
  Future<PlaceOverwriteReport?> mergeOverwriteReport({
    required String restaurantName,
    required double? latitude,
    required double? longitude,
    String? phone,
    String? website,
    String? address,
    Map<Weekday, List<OpeningHour>> operatingHours =
        const <Weekday, List<OpeningHour>>{},
  }) async {
    overwriteChecks.add(restaurantName);
    return overwriteReport;
  }

  /// What the place already on record stores for the form's name - null (the
  /// default) means "nothing matches this name", so Confirm behaves exactly
  /// as it did before that fill (see
  /// `AddLandmarkViewModel._prefillFromExistingPlace`).
  StoredPlaceDetails? storedPlace;

  /// Every name the stored-details fill looked up.
  final List<String> storedPlaceLookups = <String>[];

  @override
  Future<StoredPlaceDetails?> storedPlaceDetails({
    required String restaurantName,
    double? latitude,
    double? longitude,
  }) async {
    storedPlaceLookups.add(restaurantName);
    return storedPlace;
  }

  /// The address field's live search - stubbed to "nothing found" so a test
  /// that fills an address never reaches the geocoder.
  @override
  Future<List<AddressSuggestion>?> searchAddresses({
    required String query,
    required TouristLocation around,
  }) async => const <AddressSuggestion>[];

  @override
  Future<bool> nameMatchesSignboard({
    required List<int> imageBytes,
    required String typedName,
  }) async {
    nameChecks.add((bytes: imageBytes, typedName: typedName));
    final double? score = signboardNameScore;
    if (score == null) throw Exception('signboard check unavailable');
    return score >= LandmarkSubmissionLogic.signboardNameMatchThreshold;
  }

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
      expect(await vm.confirmRestaurant(), contains('signboard or stall'));
      expect(vm.restaurantConfirmed, isFalse);

      // Photo in place, name still blank.
      vm.setCapturedImage(_image(), 'signboard');
      expect(await vm.confirmRestaurant(), contains('restaurant name'));
      expect(vm.restaurantConfirmed, isFalse);

      vm.setRestaurantName('Tian Yi');
      expect(await vm.confirmRestaurant(), isNull);
      expect(vm.restaurantConfirmed, isTrue);
      vm.dispose();
    });

    test('submission is gated on the Confirm click', () async {
      final _TestAddLandmarkViewModel vm = await _form();

      expect(vm.canSubmit, isFalse);
      expect(vm.canSubmitReason, contains('Confirm'));

      await vm.confirmRestaurant();

      expect(vm.canSubmitReason, isNull);
      expect(vm.canSubmit, isTrue);
      vm.dispose();
    });

    test('editing the restaurant name takes the confirmation back', () async {
      final _TestAddLandmarkViewModel vm = await _form();
      await vm.confirmRestaurant();
      expect(vm.canSubmit, isTrue);

      vm.setRestaurantName('Tian Yi Seafood');

      // The old click checked the OLD name - it no longer applies.
      expect(vm.restaurantConfirmed, isFalse);
      expect(vm.canSubmit, isFalse);
      expect(vm.canSubmitReason, contains('Confirm'));

      // Confirming the NEW name passes again.
      expect(await vm.confirmRestaurant(), isNull);
      expect(vm.canSubmit, isTrue);
      vm.dispose();
    });

    test(
      'the SAME name - only spacing differs - keeps the confirmation',
      () async {
        final _TestAddLandmarkViewModel vm = await _form();
        await vm.confirmRestaurant();

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

    test('a REPLACED signboard photo takes the confirmation back', () async {
      final _TestAddLandmarkViewModel vm = await _form();
      await vm.confirmRestaurant();
      expect(vm.canSubmit, isTrue);

      // "Retake" - a different photo, even of the SAME restaurant. The name
      // is not what makes this stale, the PHOTO is: the click is what
      // checked the photo the form was holding.
      vm.setExtractedRestaurantName('Tian Yi');
      vm.setCapturedImage(_image(), 'signboard');
      expect(vm.restaurantConfirmed, isFalse);
      expect(vm.canSubmit, isFalse);
      expect(vm.canSubmitReason, contains('Confirm'));

      // Confirming the new photo passes again...
      expect(await vm.confirmRestaurant(), isNull);
      expect(vm.canSubmit, isTrue);

      // ...and cancelling the photo ("x") takes it back too - there is no
      // photo left for the click to have checked.
      vm.clearCapturedImage();
      expect(vm.restaurantConfirmed, isFalse);
      vm.dispose();
    });

    test('finds the saved submission for the same restaurant', () async {
      final _FakeLandmarkLogicFacade facade = _FakeLandmarkLogicFacade()
        ..drafts = <LandmarkDraft>[_savedDraft()];
      final _TestAddLandmarkViewModel vm = await _form(facade: facade);

      await vm.confirmRestaurant();
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

      await vm.confirmRestaurant();

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
        expect(await vm.confirmRestaurant(), isNull);
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
      await vm.confirmRestaurant();
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

      // Blank contact fields took the draft's (normalised to the stored
      // restaurant-table format).
      expect(vm.restaurantPhone, '012-345 6789');
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
      await vm.confirmRestaurant();
      final LandmarkDraft saved = (await vm.draftForRestaurantMerge())!;

      vm.mergeExistingDraft(saved);

      expect(vm.restaurantPhone, '019-000 0000');
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
      await vm.confirmRestaurant();
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

  group('the edited-name check (Confirm against the signboard)', () {
    /// A form whose signboard capture read "Tian Yi" and whose field now
    /// holds "Tian Yi Seafood" - the tourist edited Gemini's reading.
    /// [score] is what Gemini answers about that edit (null = it cannot be
    /// asked at all).
    Future<_TestAddLandmarkViewModel> editedNameForm({
      double? score = 0.96,
    }) async {
      final _FakeLandmarkLogicFacade facade = _FakeLandmarkLogicFacade()
        ..signboardNameScore = score;
      final _TestAddLandmarkViewModel vm = await _form(facade: facade);
      vm.setExtractedRestaurantName('Tian Yi');
      vm.setRestaurantName('Tian Yi Seafood');
      return vm;
    }

    test('an UNEDITED signboard reading is never sent to the check', () async {
      final _FakeLandmarkLogicFacade facade = _FakeLandmarkLogicFacade();
      final _TestAddLandmarkViewModel vm = await _form(facade: facade);
      vm.setExtractedRestaurantName('Tian Yi');

      expect(await vm.confirmRestaurant(), isNull);

      // Gemini's own reading needs no second opinion - no call, no wait.
      expect(vm.restaurantConfirmed, isTrue);
      expect(facade.nameChecks, isEmpty);
      vm.dispose();
    });

    test(
      'a CASE-only difference follows the signboard reading - no check',
      () async {
        // A score that would refuse the name if it were ever sent - it must
        // never be asked.
        final _FakeLandmarkLogicFacade facade = _FakeLandmarkLogicFacade()
          ..signboardNameScore = 0.1;
        final _TestAddLandmarkViewModel vm = await _form(facade: facade);
        vm.setExtractedRestaurantName('CUSTOM n BAnnER');
        vm.setRestaurantName('CUSTOM N BANNER');

        // Same letters, different capitals - not an edit (user request,
        // 2026-09-14).
        expect(vm.hasEditedSignboardName, isFalse);

        expect(await vm.confirmRestaurant(), isNull);

        // The reading's capitals are adopted and nothing went to Gemini.
        expect(vm.restaurantName, 'CUSTOM n BAnnER');
        expect(vm.restaurantConfirmed, isTrue);
        expect(vm.takeSignboardNameMismatch(), isFalse);
        expect(facade.nameChecks, isEmpty);
        vm.dispose();
      },
    );

    test('an edited name that still matches the signboard confirms', () async {
      final _TestAddLandmarkViewModel vm = await editedNameForm(score: 0.96);

      expect(await vm.confirmRestaurant(), isNull);

      expect(vm.restaurantConfirmed, isTrue);
      expect(vm.takeSignboardNameMismatch(), isFalse);
      // The check saw the signboard photo AND the name the tourist typed.
      expect(vm.facade.nameChecks, hasLength(1));
      expect(vm.facade.nameChecks.single.typedName, 'Tian Yi Seafood');
      expect(vm.facade.nameChecks.single.bytes, isNotEmpty);
      vm.dispose();
    });

    test('an edited name that does not match is refused, once', () async {
      final _TestAddLandmarkViewModel vm = await editedNameForm(score: 0.4);

      expect(await vm.confirmRestaurant(), isNull);

      // Not confirmed, and the View is handed the mismatch to acknowledge.
      expect(vm.restaurantConfirmed, isFalse);
      expect(vm.takeSignboardNameMismatch(), isTrue);
      expect(vm.takeSignboardNameMismatch(), isFalse); // one-shot
      expect(vm.canSubmit, isFalse);
      expect(vm.canSubmitReason, contains('Confirm'));

      // "Use the signboard name" puts Gemini's reading back, so the next
      // click passes without asking the same question again.
      vm.useSignboardName();
      expect(vm.restaurantName, 'Tian Yi');
      expect(vm.hasEditedSignboardName, isFalse);
      expect(await vm.confirmRestaurant(), isNull);
      expect(vm.restaurantConfirmed, isTrue);
      expect(vm.facade.nameChecks, hasLength(1));
      vm.dispose();
    });

    test('an unanswerable check fails OPEN - offline never blocks', () async {
      final _TestAddLandmarkViewModel vm = await editedNameForm(score: null);

      expect(await vm.confirmRestaurant(), isNull);

      expect(vm.restaurantConfirmed, isTrue);
      expect(vm.takeSignboardNameMismatch(), isFalse);
      vm.dispose();
    });

    test(
      'a STALL photo has no reading to check a typed name against',
      () async {
        final _FakeLandmarkLogicFacade facade = _FakeLandmarkLogicFacade()
          ..signboardNameScore = 0.1;
        final _TestAddLandmarkViewModel vm = await _form(facade: facade);
        // A stall capture replaces the signboard: no reading belongs to this
        // form any more, so there is nothing the name could disagree with.
        vm.setCapturedImage(_image(), 'stall');
        vm.setRestaurantName('Tian Yi Seafood');

        expect(await vm.confirmRestaurant(), isNull);

        expect(vm.restaurantConfirmed, isTrue);
        expect(facade.nameChecks, isEmpty);
        vm.dispose();
      },
    );
  });

  group('the near-duplicate place check (Confirm)', () {
    SimilarPlaceCandidate candidate({
      int id = 7,
      String name = 'Ali and Abu',
    }) => SimilarPlaceCandidate(
      id: id,
      name: name,
      isRestaurant: false,
      distanceMetres: 30,
      imageUrl: 'https://cdn.example.com/stall.jpg',
    );

    /// A form whose Confirm finds ONE similar nearby place, whose photo
    /// comparison [matches], and where the place's dishes are [existing].
    Future<_TestAddLandmarkViewModel> formWithCandidate({
      bool matches = true,
      List<String> existing = const <String>[],
    }) async {
      final _FakeLandmarkLogicFacade facade = _FakeLandmarkLogicFacade()
        ..similarPlaces = <SimilarPlaceCandidate>[candidate()]
        ..samePlacePhotoIds = matches ? <int>{7} : <int>{}
        ..existingDishNames = existing;
      final _TestAddLandmarkViewModel vm = await _form(facade: facade);
      // The search only runs while the form is watched (see
      // `AddLandmarkViewModel._findSimilarPlace`).
      vm.addListener(() {});
      return vm;
    }

    test('nothing similar nearby confirms exactly as before', () async {
      final _TestAddLandmarkViewModel vm = await _form();
      vm.addListener(() {});

      expect(await vm.confirmRestaurant(), isNull);

      expect(vm.restaurantConfirmed, isTrue);
      expect(vm.similarPlacePrompt, isNull);
      // The search ran with the form's own name.
      expect(vm.facade.similarPlaceSearches, <String>['Tian Yi']);
      vm.dispose();
    });

    test('Confirm fills the form with what the place already stores', () async {
      final _FakeLandmarkLogicFacade facade = _FakeLandmarkLogicFacade()
        ..storedPlace = const StoredPlaceDetails(
          name: 'Ali and Abu',
          phone: '03-4162 6527',
          website: 'https://ali.example',
          address: '12, Jalan Ampang, 50450 Kuala Lumpur',
          openingHours: <OpeningHour>[
            OpeningHour(
              id: 4,
              day: Weekday.monday,
              status: DayStatus.open,
              opensAt: 540,
              closesAt: 1080,
            ),
          ],
        );
      final _TestAddLandmarkViewModel vm = await _form(
        name: 'ali and abu',
        facade: facade,
      );
      vm.addListener(() {});
      final int phoneBefore = vm.phoneVersion;
      final int websiteBefore = vm.websiteVersion;
      final int addressBefore = vm.addressVersion;

      expect(await vm.confirmRestaurant(), isNull);

      // The record's own spelling of the name (its lookup ignores case)...
      expect(vm.restaurantName, 'Ali and Abu');
      // ...and what that place stores, into the fields the form left empty.
      expect(vm.restaurantPhone, '03-4162 6527');
      expect(vm.restaurantWebsite, 'https://ali.example');
      expect(vm.restaurantAddress, '12, Jalan Ampang, 50450 Kuala Lumpur');
      expect(vm.operatingHours[Weekday.monday]?.first.opensAt, 540);
      expect(vm.operatingHours[Weekday.monday]?.first.closesAt, 1080);
      // The fill must also reach the VISIBLE fields: their text controllers
      // are built once when the form opens, so each filled field moves its
      // version and `AddLandmarkView` force-syncs the controller (user
      // report, 2026-09-14: the stored details were in the form's state but
      // the input fields stayed empty).
      expect(vm.phoneVersion, phoneBefore + 1);
      expect(vm.websiteVersion, websiteBefore + 1);
      expect(vm.addressVersion, addressBefore + 1);
      // The fill ran with the form's own name, and the confirmation STANDS -
      // our own fill is not the tourist editing the signboard reading.
      expect(facade.storedPlaceLookups, <String>['ali and abu']);
      expect(vm.restaurantConfirmed, isTrue);
      vm.dispose();
    });

    test('the fill leaves what the tourist typed alone', () async {
      final _FakeLandmarkLogicFacade facade = _FakeLandmarkLogicFacade()
        ..storedPlace = const StoredPlaceDetails(
          name: 'Ali and Abu',
          phone: '03-4162 6527',
          website: 'https://ali.example',
          address: '12, Jalan Ampang, 50450 Kuala Lumpur',
        );
      final _TestAddLandmarkViewModel vm = await _form(
        name: 'Ali and Abu',
        facade: facade,
      );
      vm.addListener(() {});
      vm.setRestaurantPhone('0123456789');

      await vm.confirmRestaurant();

      // Their own entry stays exactly as typed (and normalised)...
      expect(vm.restaurantPhone, '012-345 6789');
      // ...while the fields still empty take the record's.
      expect(vm.restaurantWebsite, 'https://ali.example');
      expect(vm.restaurantAddress, '12, Jalan Ampang, 50450 Kuala Lumpur');
      vm.dispose();
    });

    test('a RESUMED confirmed form still gets the stored phone/website - its '
        'Confirm button is gone', () async {
      // The View runs this fill once when a saved submission is resumed in
      // its already-confirmed state (see
      // `AddLandmarkViewModel.fillDetailsFromPlaceOnRecord`): the Confirm row
      // reports the confirmed state instead of offering the button, so
      // without it a resumed form's phone and website would stay empty
      // (user request, 2026-09-14).
      final _FakeLandmarkLogicFacade facade = _FakeLandmarkLogicFacade()
        ..storedPlace = const StoredPlaceDetails(
          name: 'Ali and Abu',
          phone: '03-4162 6527',
          website: 'https://ali.example',
          address: '12, Jalan Ampang, 50450 Kuala Lumpur',
          openingHours: <OpeningHour>[
            OpeningHour(
              id: 4,
              day: Weekday.monday,
              status: DayStatus.open,
              opensAt: 540,
              closesAt: 1080,
            ),
          ],
        );
      final _TestAddLandmarkViewModel vm = await _form(
        name: 'Ali and Abu',
        facade: facade,
      );
      vm.addListener(() {});

      expect(vm.restaurantPhone, isEmpty);
      expect(vm.restaurantWebsite, isEmpty);

      await vm.fillDetailsFromPlaceOnRecord();

      expect(vm.restaurantPhone, '03-4162 6527');
      expect(vm.restaurantWebsite, 'https://ali.example');
      expect(vm.restaurantAddress, '12, Jalan Ampang, 50450 Kuala Lumpur');
      expect(vm.operatingHours[Weekday.monday]?.first.opensAt, 540);
      // Into the FIELDS too: both versions move, which is what the View syncs
      // its text controllers on.
      expect(vm.phoneVersion, 1);
      expect(vm.websiteVersion, 1);
      vm.dispose();
    });

    test('a matching photo asks the question INSTEAD of confirming', () async {
      final _TestAddLandmarkViewModel vm = await formWithCandidate();

      expect(await vm.confirmRestaurant(), isNull);

      // Not confirmed: the tourist answers first.
      expect(vm.restaurantConfirmed, isFalse);
      expect(vm.similarPlacePrompt?.name, 'Ali and Abu');
      expect(vm.facade.photoMatches, <int>[7]);
      vm.dispose();
    });

    test('a candidate whose photo does NOT match never asks', () async {
      final _TestAddLandmarkViewModel vm = await formWithCandidate(
        matches: false,
      );

      expect(await vm.confirmRestaurant(), isNull);

      expect(vm.similarPlacePrompt, isNull);
      expect(vm.restaurantConfirmed, isTrue);
      vm.dispose();
    });

    test('"no" keeps this form as its own new landmark', () async {
      final _TestAddLandmarkViewModel vm = await formWithCandidate();
      await vm.confirmRestaurant();

      vm.rejectSimilarPlace();

      expect(vm.restaurantConfirmed, isTrue);
      expect(vm.similarPlacePrompt, isNull);
      expect(vm.restaurantName, 'Tian Yi');
      vm.dispose();
    });

    test('"yes" adopts the place name, and SOME dishes there go', () async {
      final _TestAddLandmarkViewModel vm = await formWithCandidate(
        existing: <String>['Teh Tarik'],
      );
      vm.addAdditionalFood(_food('Teh Tarik'));
      await vm.confirmRestaurant();

      await vm.acceptSimilarPlace();

      // The stored name wins - the submit path resolves the place by name.
      expect(vm.restaurantName, 'Ali and Abu');
      expect(vm.restaurantConfirmed, isTrue);
      expect(vm.existingDishNames, <String>['Teh Tarik']);
      expect(vm.allDishesExist, isFalse);

      // Only the duplicate goes; the form keeps its own primary dish.
      expect(vm.dropExistingDishes(), <String>['Teh Tarik']);
      expect(vm.additionalFoods, isEmpty);
      expect(vm.recognizedFood?.name, 'Cendol');
      vm.dispose();
    });

    test('a dish spelled in another case is still the same dish', () async {
      // The place's own spelling comes back from the read while the form
      // holds the tourist's - the check folds case, so the duplicate is
      // recognised and dropped instead of being listed twice
      // (user request 2026-09-14).
      final _TestAddLandmarkViewModel vm = await formWithCandidate(
        existing: <String>['TEH TARIK'],
      );
      vm.addAdditionalFood(_food('teh tarik'));
      await vm.confirmRestaurant();
      await vm.acceptSimilarPlace();

      expect(vm.dropExistingDishes(), <String>['teh tarik']);
      expect(vm.additionalFoods, isEmpty);
      vm.dispose();
    });

    test('"yes" with EVERY dish there ends as nothing-to-add', () async {
      final _TestAddLandmarkViewModel vm = await formWithCandidate(
        existing: <String>['Cendol'],
      );
      await vm.confirmRestaurant();
      await vm.acceptSimilarPlace();

      expect(vm.allDishesExist, isTrue);

      await vm.finishAsAlreadyThere();

      // Nothing is left to submit, and no confirmation is outstanding.
      expect(vm.restaurantConfirmed, isFalse);
      expect(vm.existingDishNames, isEmpty);
      vm.dispose();
    });
  });

  group('the existing-details question (same-place merge)', () {
    PlaceOverwriteReport report() => const PlaceOverwriteReport(
      id: 42,
      name: 'Tian Yi',
      isRestaurant: false,
      fields: <String>['phone', 'Monday hours'],
    );

    test('a same-place record with details asks before replacing', () async {
      final _FakeLandmarkLogicFacade facade = _FakeLandmarkLogicFacade()
        ..overwriteReport = report();
      final _TestAddLandmarkViewModel vm = await _form(facade: facade);
      vm.setRestaurantPhone('012-345 6789');

      expect(await vm.checkDetailsOverwrite(), isTrue);
      expect(vm.overwritePrompt?.name, 'Tian Yi');
      expect(vm.overwritePrompt?.fieldsText, 'phone and Monday hours');

      // "Keep the existing details" - remembered, so the submit writes none
      // of it.
      vm.resolveOverwrite(false);
      expect(vm.overwritePrompt, isNull);
      expect(vm.overwriteExistingDetails, isFalse);
      vm.dispose();
    });

    test('nothing entered, and nothing to replace, never asks', () async {
      final _FakeLandmarkLogicFacade facade = _FakeLandmarkLogicFacade();
      final _TestAddLandmarkViewModel vm = await _form(facade: facade);

      // No contact details and no asserted hours: nothing a merge could
      // overwrite, so no read and no question.
      expect(await vm.checkDetailsOverwrite(), isFalse);
      expect(facade.overwriteChecks, isEmpty);

      // Something entered, but the place stores nothing to replace.
      vm.setRestaurantPhone('012-345 6789');
      expect(await vm.checkDetailsOverwrite(), isFalse);
      expect(facade.overwriteChecks, <String>['Tian Yi']);
      expect(vm.overwritePrompt, isNull);
      vm.dispose();
    });

    test('answering once is enough - editing a detail asks again', () async {
      final _FakeLandmarkLogicFacade facade = _FakeLandmarkLogicFacade()
        ..overwriteReport = report();
      final _TestAddLandmarkViewModel vm = await _form(facade: facade);
      vm.setRestaurantPhone('012-345 6789');

      await vm.checkDetailsOverwrite();
      vm.resolveOverwrite(true);
      expect(vm.overwriteExistingDetails, isTrue);

      // Same values: the answer stands, no second question.
      expect(await vm.checkDetailsOverwrite(), isFalse);

      // A DIFFERENT detail is a different decision.
      vm.setRestaurantPhone('019-000 0000');
      expect(await vm.checkDetailsOverwrite(), isTrue);
      vm.dispose();
    });

    test('the answer is acknowledged, once - the replacement waits for '
        'submit', () async {
      final _FakeLandmarkLogicFacade facade = _FakeLandmarkLogicFacade()
        ..overwriteReport = report();
      final _TestAddLandmarkViewModel vm = await _form(facade: facade);
      vm.setRestaurantPhone('012-345 6789');

      // Nothing answered yet: nothing to acknowledge.
      expect(vm.takeOverwriteAck(), isNull);

      await vm.checkDetailsOverwrite();
      vm.resolveOverwrite(true);
      final String? replaceAck = vm.takeOverwriteAck();
      expect(replaceAck, isNotNull);
      expect(replaceAck, contains('Tian Yi'));
      expect(replaceAck, contains('submit'));
      // One-shot: the notice cannot be raised twice by a rebuild.
      expect(vm.takeOverwriteAck(), isNull);

      // "Keep" says the stored record stands.
      vm.setRestaurantPhone('019-000 0000');
      await vm.checkDetailsOverwrite();
      vm.resolveOverwrite(false);
      final String? keepAck = vm.takeOverwriteAck();
      expect(keepAck, isNotNull);
      expect(keepAck, contains('Tian Yi'));
      expect(keepAck, contains('not written'));
      vm.dispose();
    });
  });
}
