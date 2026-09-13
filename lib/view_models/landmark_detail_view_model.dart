import 'package:image_picker/image_picker.dart';

import '../app/routing/app_navigator.dart';
import '../app/routing/app_routes.dart';
import '../core/base_view_model.dart';
import '../domain_model/landmark_draft.dart';
import '../domain_model/local_food.dart';
import '../domain_model/tourist_location.dart';
import '../model/business_logic/landmark_logic_facade.dart';
import 'current_location_facade.dart';
import 'food_recognition_view_model.dart'
    show AdditionalFoodCaptureResult, ExistingFormFood, LandmarkDraftHandoff;

/// ViewModel for `LandmarkDetailView`.
///
/// Read-only, full-detail look at a recognized food - reached from
/// `FoodRecognitionView`'s result popup ("View Details", A6) or from
/// `AddLandmarkView`'s "Recognised Food" card chevron.
///
/// Owns only what this screen needs: the food, its photo, and the "Add New
/// Landmark" action. Previously this screen borrowed
/// `FoodRecognitionViewModel` instead of having its own ViewModel - that
/// meant depending on a class also carrying camera-capture state
/// (isProcessing, recognitionError, multipleResults, purpose,
/// signboard/stall fields) this screen never touches. A dedicated
/// ViewModel avoids that.
///
/// Rules this class follows (see `lib/core/base_view_model.dart`):
///   * no `package:flutter/material.dart` import and no `BuildContext`;
///   * it knows the logic facade(s) below and nothing else - never a
///     repository, never a shared client, never Supabase or Gemini;
///   * state goes in private fields with read-only getters; commands wrap their
///     facade call in `runGuarded` so busy and error states behave the same on
///     every screen.
class LandmarkDetailViewModel extends BaseViewModel
    implements CurrentLocationListener {
  LandmarkDetailViewModel();

  /// Inbound: `LocationMonitor` publishes here so this screen knows where the
  /// tourist is - a new landmark may only be added on Malaysian land (A9), so
  /// an at-sea / outside-Malaysia fix blocks the "Add New Landmark" action.
  final CurrentLocationFacade locationFacade = CurrentLocationFacade();

  TouristLocation _currentLocation = TouristLocation.unknown;

  /// The most recent fix. [TouristLocation.unknown] until one arrives.
  TouristLocation get currentLocation => _currentLocation;

  @override
  void onCurrentLocationChanged(TouristLocation location) {
    _currentLocation = location;
    safeNotifyListeners();
  }

  @override
  Future<void> onInit() async {
    locationFacade.register(this);
  }

  @override
  void dispose() {
    locationFacade.unregister(this);
    super.dispose();
  }

  final LandmarkLogicFacade landmarkLogic = LandmarkLogicFacade();

  LocalFood? _recognizedFood;
  XFile? _capturedImage;

  /// Whether the recognised food is Malaysian local food. When false the
  /// details are still shown, but "Add New Landmark" must be hidden - see
  /// `LandmarkDraftHandoff.pendingIsLocalFood`.
  bool _isLocalFood = true;

  /// Whether the recognised food fits one of the app's catalogue dish types
  /// (Food/Beverage/Fruit/Dessert/Kuih). When false it is a Malaysian product
  /// at most (snack/package/canned drink) and must not be added as a landmark
  /// - see `LandmarkDraftHandoff.pendingFitsCatalogueCategory`.
  bool _fitsCatalogueCategory = true;

  /// Gemini's suggested MYR price range for the recognised food, carried
  /// onto the submitted `LandmarkItem`. `0` means unknown.
  double _priceMin = 0;
  double _priceMax = 0;

  /// Dietary restrictions (canonical names) for the recognised food, carried
  /// to the `food_dietary_restriction` association table when it becomes a
  /// new catalogue row.
  List<String> _dietaryRestrictions = const <String>[];

  /// The VARIANT name the food was seen/typed as when it EXTENDS the
  /// dictionary dish into an unlisted variant (`Cendol Jagung` -> `Cendol`) -
  /// written to `landmark_item.variant`; empty when the name IS the dish. Set
  /// from `LandmarkDraftHandoff` in the View's `initState`.
  String _variant = '';

  /// The signed-in tourist's restrictions this recognised food conflicts
  /// with - shown as a warning on the card (adding is still allowed).
  List<String> _dietaryConflicts = const <String>[];

  /// Whether the confirm button should return this food to the *existing*
  /// `AddLandmarkView` (additional-food flow) instead of pushing a fresh
  /// form (primary flow). Set from `LandmarkDraftHandoff` in the View's
  /// `initState` - see
  /// `LandmarkDraftHandoff.pendingReturnToFormAsAdditionalFood`.
  bool _returnToFormAsAdditionalFood = false;

  /// True once the additional-food flow has popped back to the form. A
  /// second "Add to Landmark" tap must not pop again - that extra pop would
  /// land on the form itself and raise its "Leave this form?" question.
  bool _returnedToForm = false;

  /// Where the food was captured - carried through, so the form this screen
  /// opens (or returns to) knows the landmark's location without waiting for
  /// a live fix.
  TouristLocation _captureLocation = TouristLocation.unknown;
  TouristLocation get captureLocation => _captureLocation;

  /// Set from `LandmarkDraftHandoff` in the View's `initState`.
  void setCaptureLocation(TouristLocation location) {
    _captureLocation = location;
  }

  /// Where the FIRST food of the landmark was captured - carried from the
  /// capture screen (see [setReferenceLocation]) so this screen re-checks
  /// the 50 m same-restaurant rule. Unknown for the primary flow (nothing to
  /// compare against yet).
  TouristLocation _referenceLocation = TouristLocation.unknown;

  /// Set from `LandmarkDraftHandoff` in the View's `initState` - see
  /// [LandmarkDraftHandoff.pendingReferenceLocation].
  void setReferenceLocation(TouristLocation location) {
    _referenceLocation = location;
  }

  /// The dishes already on the form this food would join (additional-food
  /// flow) - see [LandmarkDraftHandoff.pendingExistingFormFoods]; empty for
  /// the primary flow.
  List<ExistingFormFood> _existingFormFoods = const <ExistingFormFood>[];

  /// Set from `LandmarkDraftHandoff` in the View's `initState` - see
  /// [LandmarkDraftHandoff.pendingExistingFormFoods].
  void setExistingFormFoods(List<ExistingFormFood> foods) {
    _existingFormFoods = List<ExistingFormFood>.unmodifiable(foods);
  }

  /// Whether this food was captured more than 50 m from the first food, so
  /// it is not the same restaurant. False when either spot is unknown -
  /// the same fail-open rule the capture screen applies.
  bool get isCaptureOutOfRange => !landmarkLogic.isSameRestaurantCaptureRange(
    _referenceLocation,
    _captureLocation,
  );

  /// Why this food cannot join the landmark - the same message the capture
  /// screen shows for the same rejection. Null when the capture is in range.
  String? get captureRangeBlockMessage => isCaptureOutOfRange
      ? landmarkLogic.captureTooFarMessage('This food')
      : null;

  /// Why this food cannot join the form - it is ALREADY on it (the same
  /// duplicate rule the capture screen applies, see
  /// `LandmarkSubmissionLogic.isSameDishAndVariant`). Only meaningful for
  /// the additional-food return ([returnToFormAsAdditionalFood]); null
  /// otherwise, and while the dish is not a duplicate.
  String? get duplicateFormFoodBlockMessage {
    if (!_returnToFormAsAdditionalFood) return null;
    final LocalFood? food = _recognizedFood;
    if (food == null) return null;
    for (final ExistingFormFood existing in _existingFormFoods) {
      if (landmarkLogic.isSameDishAndVariant(
        existing.food,
        existing.variant,
        food,
        _variant,
      )) {
        return landmarkLogic.duplicateFoodNotice;
      }
    }
    return null;
  }

  LocalFood? get recognizedFood => _recognizedFood;
  XFile? get capturedImage => _capturedImage;
  bool get isLocalFood => _isLocalFood;
  bool get fitsCatalogueCategory => _fitsCatalogueCategory;
  bool get returnToFormAsAdditionalFood => _returnToFormAsAdditionalFood;
  double get priceMin => _priceMin;
  double get priceMax => _priceMax;
  List<String> get dietaryRestrictions => _dietaryRestrictions;

  /// The VARIANT name the food was seen/typed as when it EXTENDS the
  /// dictionary dish into an unlisted variant (`Cendol Jagung` -> `Cendol`) -
  /// shown on the Recognised Food card; empty when the name IS the dish.
  String get variant => _variant;
  List<String> get dietaryConflicts => _dietaryConflicts;

  /// Whether the current fix makes adding a landmark impossible (A9) - a new
  /// landmark may only be added on Malaysian land, so a fix at sea or outside
  /// Malaysia blocks it. `false` when there is no fix yet (nothing to judge).
  bool get isAddLandmarkBlockedByLocation =>
      _currentLocation.isKnown &&
      !landmarkLogic.isOnLand(
        _currentLocation.latitude,
        _currentLocation.longitude,
      );

  /// Why "Add New Landmark" is unavailable for the current spot - shown on
  /// this screen in place of the add prompt. Null when the location allows
  /// adding.
  String? get addLandmarkLocationBlockMessage =>
      isAddLandmarkBlockedByLocation ? _offLandAddMessage : null;

  static const String _offLandAddMessage =
      'New landmarks can only be added on Malaysian land - you are at sea or '
      'outside Malaysia, so a landmark cannot be added here.';

  void setIsLocalFood(bool value) {
    _isLocalFood = value;
  }

  void setFitsCatalogueCategory(bool value) {
    _fitsCatalogueCategory = value;
  }

  void setPriceRange({required double priceMin, required double priceMax}) {
    _priceMin = priceMin;
    _priceMax = priceMax;
  }

  void setDietaryRestrictions(List<String> dietaryRestrictions) {
    _dietaryRestrictions = dietaryRestrictions;
  }

  void setVariant(String variant) {
    _variant = variant;
  }

  void setDietaryRestrictionConflicts(List<String> conflicts) {
    _dietaryConflicts = conflicts;
  }

  void setReturnToFormAsAdditionalFood(bool value) {
    _returnToFormAsAdditionalFood = value;
  }

  /// Set from `LandmarkDraftHandoff` in the View's `initState`, before
  /// `onInit()` - see that class's doc.
  void setRecognizedFood(LocalFood food) {
    _recognizedFood = food;
    safeNotifyListeners();
  }

  /// Set alongside [setRecognizedFood] - see
  /// `LandmarkDraftHandoff.pendingCapturedImage`.
  void setCapturedImage(XFile image) {
    _capturedImage = image;
    safeNotifyListeners();
  }

  /// "Add New Landmark" (primary flow) or "Add to Landmark" (additional-food
  /// flow) - hands the recognized food (and its photo) onward. The primary
  /// flow pushes a fresh `AddLandmarkView`; the additional-food flow pops the
  /// detail screen and the camera screen back to the *existing* form, handing
  /// the food back through [AdditionalFoodCaptureResult] (see
  /// [_returnToFormAsAdditionalFood]).
  ///
  /// Like the camera screen, the primary flow first checks the saved
  /// incomplete submissions: this dish at this spot continuing an existing
  /// form beats stacking a second draft of the same visit.
  Future<void> proceedToAddLandmark() async {
    final LocalFood? food = _recognizedFood;
    if (food == null) return;
    // A non-local food - or a Malaysian product that isn't a catalogue dish
    // type (snack/package/canned drink) - is never allowed to become a
    // landmark - the UI hides the button, this guard is the second line of
    // defence.
    if (!_isLocalFood || !_fitsCatalogueCategory) return;
    // Captured more than 50 m from the first food (50 m same-restaurant
    // rule) - not this restaurant's food. The capture screen already
    // withholds its add button; this screen must withhold BOTH of its
    // paths - the additional-food return below AND opening a new form -
    // otherwise opening "View Details" would be a way around the block.
    if (isCaptureOutOfRange) return;
    // Already on the form (the duplicate rule) - the capture screen already
    // withheld its button for this; this screen must not be a way around
    // that block either.
    if (duplicateFormFoodBlockMessage != null) return;
    if (_returnToFormAsAdditionalFood) {
      final XFile? image = _capturedImage;
      if (image == null) return;
      if (_returnedToForm) return;
      _returnedToForm = true;
      // Pop LandmarkDetailView, then pop the FoodRecognitionView below it
      // WITH the result - which completes `AddLandmarkViewModel.openAddMoreFood`'s
      // await, so the food lands in the existing form's additional-foods list.
      AppNavigator.pop();
      AppNavigator.pop<AdditionalFoodCaptureResult>((
        food: food,
        image: image,
        priceMin: _priceMin,
        priceMax: _priceMax,
        captureLocation: _captureLocation,
        variant: _variant,
        dietaryRestrictions: _dietaryRestrictions,
      ));
      return;
    }
    // A new landmark may only be added on Malaysian land (A9) - while the fix
    // is at sea / outside Malaysia the UI hides the button and this guard is
    // the second line of defence. (The additional-food return above is not
    // gated: it hands food back to an already-open form, which enforces the
    // same rule itself.)
    if (isAddLandmarkBlockedByLocation) return;
    LandmarkDraftHandoff().pushAddLandmark(
      food,
      _capturedImage,
      isLocalFood: _isLocalFood,
      priceMin: _priceMin,
      priceMax: _priceMax,
      dietaryRestrictions: _dietaryRestrictions,
      dietaryConflicts: _dietaryConflicts,
      variant: _variant,
      captureLocation: _captureLocation,
    );
  }

  /// The saved submission the current capture could CONTINUE, or null - the
  /// same rule as the camera screen's (`FoodRecognitionViewModel
  /// .draftToContinue`): the SAME dish + variant + capture spot (50 m). The
  /// View asks "continue your unfinished submission?" when this returns a
  /// draft.
  Future<LandmarkDraft?> draftToContinue() async {
    final LocalFood? food = _recognizedFood;
    if (food == null) return null;
    try {
      final List<LandmarkDraft> drafts = await landmarkLogic
          .pendingLandmarkDrafts();
      return landmarkLogic.matchingLandmarkDraft(
        drafts: drafts,
        food: food,
        captureLocation: _captureLocation,
        variant: _variant,
      );
    } catch (_) {
      // Best-effort - a fresh form is always a safe fallback.
      return null;
    }
  }

  /// Reopens [draft] pre-filled - the tourist chose "Continue submission" in
  /// the continue prompt.
  void openDraft(LandmarkDraft draft) {
    LandmarkDraftHandoff().pendingDraft = draft;
    AppNavigator.push(AppRoutes.addLandmark);
  }
}
