import 'package:image_picker/image_picker.dart';
import 'package:meta/meta.dart' show protected, visibleForTesting;

import '../app/routing/app_navigator.dart';
import '../app/routing/app_routes.dart';
import '../core/base_view_model.dart';
import '../domain_model/food_recognition_result.dart';
import '../domain_model/landmark_draft.dart';
import '../domain_model/local_food.dart';
import '../domain_model/tourist_location.dart';
import '../model/business_logic/landmark_logic_facade.dart';
import 'current_location_facade.dart';

/// Temporary hand-off point for data crossing a route push into a BRAND NEW
/// ViewModel.
///
/// Routes pass no arguments (Developer Guideline, section 7.2 "Open
/// decision") and a ViewModel takes no constructor parameters (Rule 1). So
/// when one screen wants to open another with data already in hand, the
/// pushing side writes here right before navigating, and the new View
/// reads-and-clears it in `initState`, *before* `onInit()` runs:
///
/// ```dart
/// // Before pushing:
/// LandmarkDraftHandoff().pendingRecognizedFood = recognizedFood;
/// AppNavigator.push(AppRoutes.addLandmark);
///
/// // In AddLandmarkView.initState():
/// _viewModel = AddLandmarkViewModel();
/// final food = LandmarkDraftHandoff().takeRecognizedFood();
/// if (food != null) _viewModel.setRecognizedFood(food);
/// _viewModel.onInit();
/// ```
///
/// This only covers the FORWARD direction (data going INTO a screen that is
/// about to construct a fresh ViewModel). It is not needed for a screen that
/// is pushed and later pops back with a result - that data rides the
/// `Future<T?>` that `AppNavigator.push<T>` / `.pop<T>` already return (see
/// [FoodRecognitionPurpose], [LandmarkImageCaptureResult] and
/// `confirmFoodAndReturn`/`confirmCaptureAndReturn` below, used when this
/// same screen is reused for signboard/stall/additional-food capture from
/// `AddLandmarkView`, which stays on the stack while it waits).
///
/// A singleton, like the other cross-screen facades - `LandmarkDraftHandoff()`
/// always returns the same instance. `take...` clears what it read, so a
/// later, unrelated navigation never picks up stale data left over from a
/// previous trip through the flow.
class LandmarkDraftHandoff {
  factory LandmarkDraftHandoff() => _instance;

  LandmarkDraftHandoff._();

  static final LandmarkDraftHandoff _instance = LandmarkDraftHandoff._();

  LocalFood? pendingRecognizedFood;

  /// The just-captured photo, carried alongside [pendingRecognizedFood] so
  /// `LandmarkDetailView` can show the same thumbnail the tourist saw
  /// in the capture popup, instead of nothing.
  XFile? pendingCapturedImage;

  /// What this push of `FoodRecognitionView` is for. Unset (null) means the
  /// plain, initial "capture a food photo" entry point - the screen defaults
  /// to [FoodRecognitionPurpose.food] when nothing is pending.
  FoodRecognitionPurpose? pendingPurpose;

  /// Set by `FoodRecognitionViewModel.proceedToViewDetails` when the camera
  /// was opened in [FoodRecognitionPurpose.additionalFood] mode, before it
  /// pushes the detail screen. `LandmarkDetailView` reads this in `initState`
  /// so its confirm button returns the food to the *existing* `AddLandmarkView`
  /// (popping the camera + detail screens with an
  /// [AdditionalFoodCaptureResult]) instead of pushing a brand-new form.
  bool pendingReturnToFormAsAdditionalFood = false;

  /// Whether [pendingRecognizedFood] was judged by Gemini to be Malaysian
  /// local food. When false, the detail screen still shows the food but must
  /// not offer "Add New Landmark" - see [FoodRecognitionResult.isLocalFood].
  /// Defaults to true (the common case).
  bool pendingIsLocalFood = true;

  /// Whether [pendingRecognizedFood] fits one of the app's catalogue dish
  /// types (Food/Beverage/Fruit/Dessert/Kuih). When false it is a Malaysian
  /// product at most (snack/package/canned drink) and must not be offered as
  /// a landmark - see `FoodRecognitionResult.fitsCatalogueCategory`. Defaults
  /// to true (the common case).
  bool pendingFitsCatalogueCategory = true;

  /// Gemini's suggested MYR price range for [pendingRecognizedFood], carried
  /// onto the submitted `LandmarkItem`. `0` means unknown.
  double pendingPriceMin = 0;
  double pendingPriceMax = 0;

  /// Gemini's confidence (0..1) in [pendingRecognizedFood]'s dish name. Set by
  /// the recognition screen so `AddLandmarkView` can attach it to the
  /// submitted food, where the catalogue-growth gate (`FoodRecognitionLogic
  /// .registerNewDishes`) demands a HIGH bar before writing a new `local_food`
  /// row. `0` means unknown/never catalogue-insert eligible. Survives the
  /// detail-screen round trip because `pushAddLandmark` only overwrites it
  /// when a value is explicitly passed.
  double pendingConfidence = 0;

  /// Dietary restrictions (canonical `dietary_restriction.restriction_name`
  /// strings) for [pendingRecognizedFood], carried to the
  /// `food_dietary_restriction` association table when it becomes a new
  /// catalogue row - NOT a `local_food` column, so it does not ride on
  /// `LocalFood`.
  List<String> pendingDietaryRestrictions = const <String>[];

  /// The VARIANT name [pendingRecognizedFood] was actually seen/typed as,
  /// when it EXTENDS the dictionary dish into an unlisted variant (`Cendol
  /// Jagung` resolving to the curated `Cendol`). Written to
  /// `landmark_item.variant`; empty when the name IS the dish - see
  /// `FoodRecognitionResult.variant`.
  String pendingVariant = '';

  /// The signed-in tourist's dietary restrictions that [pendingRecognizedFood]
  /// conflicts with - carried so the "Add New Landmark" form keeps warning
  /// (adding is still allowed) until the food is submitted.
  List<String> pendingDietaryConflicts = const <String>[];

  /// Where the tourist stood when the food photo was captured - the
  /// landmark's location (the form's pin defaults here) and the reference
  /// every later capture is checked against (50 m same-restaurant rule).
  /// Null when no fix was available at capture time.
  TouristLocation? pendingCaptureLocation;

  /// Where the FIRST food of the landmark currently being added was
  /// captured. Set when this screen is pushed for an additional food /
  /// signboard / stall capture, so that new capture can be compared with it
  /// - a capture further than 50 m away cannot belong to the same
  /// restaurant and is rejected (see `FoodRecognitionViewModel`'s
  /// capture-range gate). Also carried into `LandmarkDetailView` (see
  /// [pushLandmarkDetail]), whose add action re-checks the same rule so
  /// "View Details" can never bypass the block.
  TouristLocation? pendingReferenceLocation;

  /// The dishes ALREADY on the form an additional-food capture is for.
  /// Handed over by `AddLandmarkViewModel.openAddMoreFood` and read (then
  /// cleared) by `FoodRecognitionViewModel`, so a re-captured duplicate is
  /// blocked ON THE SPOT - "Add to Landmark" is withheld and the reason is
  /// shown right there - instead of bouncing the tourist back with a notice
  /// on the form. Also carried into `LandmarkDetailView` (see
  /// [pushLandmarkDetail]), whose add action re-checks the same rule so
  /// "View Details" can never bypass the block.
  List<ExistingFormFood> pendingExistingFormFoods = const <ExistingFormFood>[];

  /// The saved (incomplete) form the tourist chose to continue - read by
  /// `AddLandmarkView.initState` when the form was opened from the draft
  /// list, or auto-continued because the same dish was captured again.
  LandmarkDraft? pendingDraft;

  LocalFood? takeRecognizedFood() {
    final LocalFood? value = pendingRecognizedFood;
    pendingRecognizedFood = null;
    return value;
  }

  XFile? takeCapturedImage() {
    final XFile? value = pendingCapturedImage;
    pendingCapturedImage = null;
    return value;
  }

  FoodRecognitionPurpose takePurpose() {
    final FoodRecognitionPurpose value =
        pendingPurpose ?? FoodRecognitionPurpose.food;
    pendingPurpose = null;
    return value;
  }

  bool takeReturnToFormAsAdditionalFood() {
    final bool value = pendingReturnToFormAsAdditionalFood;
    pendingReturnToFormAsAdditionalFood = false;
    return value;
  }

  bool takeIsLocalFood() {
    final bool value = pendingIsLocalFood;
    pendingIsLocalFood = true;
    return value;
  }

  bool takeFitsCatalogueCategory() {
    final bool value = pendingFitsCatalogueCategory;
    pendingFitsCatalogueCategory = true;
    return value;
  }

  double takePriceMin() {
    final double value = pendingPriceMin;
    pendingPriceMin = 0;
    return value;
  }

  double takePriceMax() {
    final double value = pendingPriceMax;
    pendingPriceMax = 0;
    return value;
  }

  double takeConfidence() {
    final double value = pendingConfidence;
    pendingConfidence = 0;
    return value;
  }

  List<String> takeDietaryRestrictions() {
    final List<String> value = pendingDietaryRestrictions;
    pendingDietaryRestrictions = const <String>[];
    return value;
  }

  String takeVariant() {
    final String value = pendingVariant;
    pendingVariant = '';
    return value;
  }

  List<String> takeDietaryConflicts() {
    final List<String> value = pendingDietaryConflicts;
    pendingDietaryConflicts = const <String>[];
    return value;
  }

  /// The capture-time location, or [TouristLocation.unknown] when none was
  /// recorded.
  TouristLocation takeCaptureLocation() {
    final TouristLocation? value = pendingCaptureLocation;
    pendingCaptureLocation = null;
    return value ?? TouristLocation.unknown;
  }

  /// The first food's capture location for an additional/signboard/stall
  /// capture, or [TouristLocation.unknown] when there is none (nothing to
  /// compare against - the capture is always allowed).
  TouristLocation takeReferenceLocation() {
    final TouristLocation? value = pendingReferenceLocation;
    pendingReferenceLocation = null;
    return value ?? TouristLocation.unknown;
  }

  /// The dishes already on the form this capture returns to - see
  /// [pendingExistingFormFoods].
  List<ExistingFormFood> takeExistingFormFoods() {
    final List<ExistingFormFood> value = pendingExistingFormFoods;
    pendingExistingFormFoods = const <ExistingFormFood>[];
    return value;
  }

  /// The saved form to resume, or null when this is a fresh capture.
  LandmarkDraft? takeDraft() {
    final LandmarkDraft? value = pendingDraft;
    pendingDraft = null;
    return value;
  }

  /// Stashes [food] and [image] for the food-detail screen
  /// (`LandmarkDetailView`, at `AppRoutes.landmarkDetail`) and navigates
  /// there - the shared implementation of "go view details for this
  /// recognized food", called by
  /// `FoodRecognitionViewModel.proceedToViewDetails`. The first food's
  /// capture spot ([referenceLocation], when there is one) rides along so
  /// the detail screen re-checks the 50 m same-restaurant rule itself, and
  /// [existingFormFoods] rides along so it re-checks the duplicate rule too.
  void pushLandmarkDetail(
    LocalFood food,
    XFile? image, {
    bool isLocalFood = true,
    bool fitsCatalogueCategory = true,
    double priceMin = 0,
    double priceMax = 0,
    double confidence = 0,
    List<String> dietaryRestrictions = const <String>[],
    List<String> dietaryConflicts = const <String>[],
    String variant = '',
    TouristLocation captureLocation = TouristLocation.unknown,
    TouristLocation referenceLocation = TouristLocation.unknown,
    List<ExistingFormFood> existingFormFoods = const <ExistingFormFood>[],
  }) {
    pendingRecognizedFood = food;
    pendingCapturedImage = image;
    pendingIsLocalFood = isLocalFood;
    pendingFitsCatalogueCategory = fitsCatalogueCategory;
    pendingPriceMin = priceMin;
    pendingPriceMax = priceMax;
    pendingDietaryRestrictions = dietaryRestrictions;
    pendingDietaryConflicts = dietaryConflicts;
    pendingVariant = variant;
    // The capture spot rides along so the detail screen can hand it to the
    // form it eventually opens.
    pendingCaptureLocation = captureLocation.isKnown ? captureLocation : null;
    // The first food's spot (additional-food flow) rides along too, so the
    // detail screen re-checks the 50 m same-restaurant rule itself - a food
    // the camera screen blocked must stay blocked here ("View Details" must
    // never be a way around it).
    pendingReferenceLocation = referenceLocation.isKnown
        ? referenceLocation
        : null;
    // The form's own dishes ride along too, so the detail screen re-checks
    // the duplicate rule itself - "View Details" must never be a way
    // around the block either.
    pendingExistingFormFoods = existingFormFoods;
    // Only overwrite when a real confidence is passed - a later re-push
    // without one (e.g. from the detail screen) must keep the value set here.
    if (confidence > 0) pendingConfidence = confidence;
    AppNavigator.push(AppRoutes.landmarkDetail);
  }

  /// Stashes [food] and [image] for `AddLandmarkView` and navigates there -
  /// the shared implementation of "proceed to add this as a landmark".
  /// `FoodRecognitionViewModel.proceedToAddLandmark` and
  /// `LandmarkDetailViewModel.proceedToAddLandmark` both call this for the
  /// same reason [pushLandmarkDetail] is shared rather than duplicated.
  void pushAddLandmark(
    LocalFood food,
    XFile? image, {
    bool isLocalFood = true,
    bool fitsCatalogueCategory = true,
    double priceMin = 0,
    double priceMax = 0,
    double confidence = 0,
    List<String> dietaryRestrictions = const <String>[],
    List<String> dietaryConflicts = const <String>[],
    String variant = '',
    TouristLocation captureLocation = TouristLocation.unknown,
  }) {
    pendingRecognizedFood = food;
    pendingCapturedImage = image;
    pendingIsLocalFood = isLocalFood;
    pendingFitsCatalogueCategory = fitsCatalogueCategory;
    pendingPriceMin = priceMin;
    pendingPriceMax = priceMax;
    pendingDietaryRestrictions = dietaryRestrictions;
    pendingDietaryConflicts = dietaryConflicts;
    pendingVariant = variant;
    // Where the food was captured - the landmark's location, carried to the
    // form so it does not have to wait for a live fix (see
    // `AddLandmarkViewModel.baseLocation`).
    pendingCaptureLocation = captureLocation.isKnown ? captureLocation : null;
    // Only overwrite when a real confidence is passed - see pushLandmarkDetail.
    if (confidence > 0) pendingConfidence = confidence;
    AppNavigator.push(AppRoutes.addLandmark);
  }

  /// Clears everything. Call after a successful submission or an explicit
  /// cancel, so a later "Add New Landmark" never starts pre-filled with a
  /// previous attempt's leftovers.
  void clear() {
    pendingRecognizedFood = null;
    pendingCapturedImage = null;
    pendingPurpose = null;
    pendingReturnToFormAsAdditionalFood = false;
    pendingIsLocalFood = true;
    pendingFitsCatalogueCategory = true;
    pendingPriceMin = 0;
    pendingPriceMax = 0;
    pendingConfidence = 0;
    pendingDietaryRestrictions = const <String>[];
    pendingDietaryConflicts = const <String>[];
    pendingVariant = '';
    pendingCaptureLocation = null;
    pendingReferenceLocation = null;
    pendingExistingFormFoods = const <ExistingFormFood>[];
    pendingDraft = null;
  }
}

/// What `FoodRecognitionView` is being used to capture this time - the same
/// camera screen is reused for all four (see [LandmarkDraftHandoff]):
///   * [food] - the primary, initial entry point. Pushes forward to
///     `AddLandmarkView` / `LandmarkDetailView` on success.
///   * [additionalFood] - "Add More Food" (A12), pushed from an
///     `AddLandmarkView` that already exists on the stack. Pops back with
///     the recognized `LocalFood` instead of pushing forward.
///   * [signboard] / [stall] - pushed the same way; pop back with a
///     [LandmarkImageCaptureResult].
enum FoodRecognitionPurpose { food, additionalFood, signboard, stall }

/// What this screen hands back to `AddLandmarkView` when reused for
/// signboard/stall capture. `AddLandmarkView` already exists on the
/// navigation stack (it pushed this screen), so the result rides the
/// `Future<T?>` that `AppNavigator.push<T>` returns on pop - no shared
/// hand-off object needed for this direction.
typedef LandmarkImageCaptureResult = ({
  XFile image,
  String imageType, // 'signboard' or 'stall'
  String? extractedRestaurantName, // set only when imageType == 'signboard'
  /// Where the photo was captured - checked against the first food's
  /// location (50 m same-restaurant rule) before the form may use it.
  TouristLocation captureLocation,
});

/// One dish already on the form an additional-food capture returns to: the
/// dish itself (name, catalogue id and synonyms) plus the variant it was
/// recorded with - exactly what the shared "is this the same thing to add?"
/// rule needs (see `LandmarkSubmissionLogic.isSameDishAndVariant`).
typedef ExistingFormFood = ({LocalFood food, String variant});

/// What this screen hands back to `AddLandmarkView` when reused for
/// additional-food capture - the recognized food AND its own photo, so
/// `LandmarkItem.imageUrl`/`imageId` has somewhere to eventually come from
/// for that food too (previously only the primary food's photo was ever
/// tracked - this was a real gap, not an intentional asymmetry).
typedef AdditionalFoodCaptureResult = ({
  LocalFood food,
  XFile image,
  double priceMin,
  double priceMax,
  TouristLocation captureLocation,

  /// The observed/typed variant name when it EXTENDS the dictionary dish
  /// into an unlisted variant, and the dietary tags that apply to THIS food -
  /// both recorded on the additional `landmark_item` (see
  /// `LandmarkItem.variant` / `dietaryRestrictions`).
  String variant,
  List<String> dietaryRestrictions,
});

/// ViewModel for `FoodRecognitionView` (also pushed from `AddLandmarkView`
/// in signboard/stall/additional-food capture mode - see
/// [FoodRecognitionPurpose]).
///
/// Camera capture and recognition via Gemini. Handles: capture image → send
/// to Gemini → display result.
///
/// Rules this class follows (see `lib/core/base_view_model.dart`):
///   * no `package:flutter/material.dart` import and no `BuildContext`;
///   * it knows the logic facade(s) below and nothing else - never a
///     repository, never a shared client, never Supabase or Gemini;
///   * state goes in private fields with read-only getters; commands wrap their
///     facade call in `runGuarded` so busy and error states behave the same on
///     every screen.
class FoodRecognitionViewModel extends BaseViewModel
    implements CurrentLocationListener {
  FoodRecognitionViewModel();

  /// Inbound: `LocationMonitor` publishes here so this screen knows where the
  /// tourist is - a new landmark may only be added on Malaysian land (A9), so
  /// an at-sea / outside-Malaysia fix blocks the "Add New Landmark" action.
  final CurrentLocationFacade locationFacade = CurrentLocationFacade();

  TouristLocation _currentLocation = TouristLocation.unknown;

  /// The most recent fix. [TouristLocation.unknown] until one arrives.
  TouristLocation get currentLocation => _currentLocation;

  /// Where the tourist stood when the CURRENT photo was captured. Unlike
  /// [_currentLocation] (which keeps updating as they walk), this is frozen
  /// at capture time - it is the landmark's location and the spot every
  /// later capture of the same landmark is measured against (50 m rule).
  TouristLocation _captureLocation = TouristLocation.unknown;
  TouristLocation get captureLocation => _captureLocation;

  /// Where the FIRST food of the landmark this screen is feeding was
  /// captured - set from `LandmarkDraftHandoff` before `onInit()` when this
  /// push is an additional food / signboard / stall capture. Unknown for the
  /// primary capture (nothing to compare against yet).
  TouristLocation _referenceLocation = TouristLocation.unknown;

  /// Why the last capture cannot join the landmark - non-null when it was
  /// taken further than 50 m from the first food's location, so it is not
  /// the same restaurant. The result stays visible, but the confirm/add
  /// action is withheld so the tourist captures it again on site.
  String? _captureRangeError;
  String? get captureRangeError => _captureRangeError;

  /// Whether the current capture was rejected by the same-restaurant range
  /// check (see [_captureRangeError]).
  bool get isCaptureOutOfRange => _captureRangeError != null;

  /// Set from `LandmarkDraftHandoff` in the View's `initState`, before
  /// `onInit()` - see [LandmarkDraftHandoff.pendingReferenceLocation].
  void setReferenceLocation(TouristLocation location) {
    _referenceLocation = location;
    safeNotifyListeners();
  }

  /// The dishes already on the form this capture returns to - see
  /// [LandmarkDraftHandoff.pendingExistingFormFoods]. Empty for the primary
  /// flow (no form exists yet).
  List<ExistingFormFood> _existingFormFoods = const <ExistingFormFood>[];

  /// Set from `LandmarkDraftHandoff` in the View's `initState`, before
  /// `onInit()` - see [LandmarkDraftHandoff.pendingExistingFormFoods].
  void setExistingFormFoods(List<ExistingFormFood> foods) {
    _existingFormFoods = List<ExistingFormFood>.unmodifiable(foods);
    safeNotifyListeners();
  }

  /// The signed-in tourist's saved (incomplete) landmark forms, loaded when
  /// this screen opens for a fresh capture ([FoodRecognitionPurpose.food]).
  /// The View reminds the tourist that they can continue one from the
  /// Profile screen - it never continues or deletes one from here.
  List<LandmarkDraft> _pendingDrafts = const <LandmarkDraft>[];
  List<LandmarkDraft> get pendingDrafts =>
      List<LandmarkDraft>.unmodifiable(_pendingDrafts);
  bool get hasPendingDrafts => _pendingDrafts.isNotEmpty;

  @override
  void onCurrentLocationChanged(TouristLocation location) {
    _currentLocation = location;
    safeNotifyListeners();
  }

  @protected
  LandmarkLogicFacade createLandmarkLogic() => LandmarkLogicFacade();

  late final LandmarkLogicFacade landmarkLogic = createLandmarkLogic();

  /// How long the "Analysing image..." loading state must stay up at minimum
  /// after a capture / manual name entry / picker enrichment starts. Gemini
  /// itself can take longer - this only guarantees a FLOOR, so the
  /// recognised-food card (and the "View Details" data carried with it) is
  /// never shown while the result is still settling. `Duration.zero` in
  /// tests, so they don't each wait out the floor.
  @protected
  Duration get minimumLoadingDuration => const Duration(seconds: 3);

  // --- MODE ---
  FoodRecognitionPurpose _purpose = FoodRecognitionPurpose.food;
  FoodRecognitionPurpose get purpose => _purpose;

  /// Set from `LandmarkDraftHandoff` in the View's `initState`, before
  /// `onInit()` - see [LandmarkDraftHandoff].
  void setPurpose(FoodRecognitionPurpose purpose) {
    _purpose = purpose;
    notifyListeners();
  }

  // --- FOOD RECOGNITION STATE ---
  XFile? _capturedImage;
  LocalFood? _recognizedFood;
  List<LocalFood> _multipleResults = [];
  String? _recognitionError;
  bool _isProcessing = false;

  /// True once this screen has popped itself back to its caller. A second
  /// "Confirm" tap (or a stray repeat) must be a no-op: the extra pop would
  /// land on the route BELOW this screen - the Add-Landmark form - which is
  /// how a "Leave this form?" question used to appear out of nowhere right
  /// after a capture was confirmed.
  bool _hasReturned = false;

  /// Whether this screen has already popped itself back to its caller (see
  /// [confirmFoodAndReturn]/[confirmCaptureAndReturn] - they must return
  /// exactly once; a second pop would land on the Add-Landmark form below).
  @visibleForTesting
  bool get hasReturned => _hasReturned;

  // --- dev GPS mock (presenter tool, Android only) -------------------------
  //
  // The capture screen drives the SAME mock singleton the dashboard drives,
  // so a mock set here (or there) is live in both. `LocationMonitor`
  // publishes the mocked fix, so [_currentLocation] - and therefore every
  // capture's location, which is frozen at capture time - follows it. The
  // "walk 60 m" chips in `MockGpsButton` nudge from [currentLocation], which
  // makes the 50 m same-restaurant demo a one-tap affair: capture the first
  // food, walk 60 m away, capture the next and watch the rule fire.

  /// Whether this build can mock the OS GPS (Android, non-web).
  bool get mockGpsSupported => landmarkLogic.mockGpsSupported;

  /// Whether a mock is live right now.
  bool get mockGpsActive => landmarkLogic.mockGpsActive;

  /// Teleports the OS GPS. Returns an error message, or null on success.
  Future<String?> setMockGps({
    required double latitude,
    required double longitude,
  }) async {
    final String? error = await landmarkLogic.setMockGps(
      latitude: latitude,
      longitude: longitude,
    );
    safeNotifyListeners();
    return error;
  }

  /// Stops mocking and lets the real GPS drive again.
  Future<void> stopMockGps() async {
    await landmarkLogic.stopMockGps();
    safeNotifyListeners();
  }

  /// Whether the recognised food is Malaysian local food. When false the
  /// result is still shown (and "View Details" works) but the tourist must
  /// not be allowed to add it as a landmark.
  bool _isLocalFood = true;

  /// Whether the recognised food fits one of the app's catalogue dish types
  /// (Food/Beverage/Fruit/Dessert/Kuih). When false it is a Malaysian
  /// product at most (snack/package/canned drink) and must not be added as a
  /// landmark - see `FoodRecognitionResult.fitsCatalogueCategory`.
  bool _fitsCatalogueCategory = true;

  /// Gemini's suggested MYR price range for the recognised food - carried
  /// onto the submitted `LandmarkItem` (see `FoodRecognitionResult`).
  double _priceMin = 0;
  double _priceMax = 0;

  /// Dietary restrictions (canonical names) for the recognised food, carried
  /// to the `food_dietary_restriction` association table when it becomes a
  /// new catalogue row - NOT on `LocalFood` (dietary is an association).
  List<String> _dietaryRestrictions = const <String>[];

  /// The VARIANT name the recognised food was seen/typed as, when it EXTENDS
  /// the dictionary dish into an unlisted variant (`Cendol Jagung` -> curated
  /// `Cendol`) - carried onto `landmark_item.variant` (see
  /// `FoodRecognitionResult.variant`).
  String _variant = '';

  /// Dietary restriction names (e.g. "No Pork") the signed-in tourist holds
  /// (`user_dietary_restriction`) - loaded once on init so a recognised dish
  /// that conflicts can warn on the result card (adding is still allowed).
  List<String> _userDietaryRestrictions = const <String>[];

  /// Of [_userDietaryRestrictions], the ones the recognised food conflicts
  /// with (matched against [_dietaryRestrictions]).
  List<String> _dietaryConflicts = const <String>[];

  /// Gemini's confidence (0..1) in the recognised food - surfaced in the UI
  /// so a shaky result is never presented as certain. For manual name entry
  /// this is the name-vs-photo verification confidence, so a name Gemini
  /// can't confirm comes back low and the low-confidence cue fires. `1.0`
  /// when unknown (picker selection - the tourist chose).
  double _confidence = 1.0;

  /// Whether a manually-typed name was verified against the photo and found
  /// NOT to match it (with decent confidence) - the card warns "this photo
  /// doesn't look like X" and the typed name can NOT be added; the tourist
  /// can only keep the detected food.
  bool _nameMismatch = false;

  /// What the photo actually shows, in Gemini's words, when [_nameMismatch].
  /// DIAGNOSTIC only - the mismatch UI deliberately names just two dishes:
  /// what was typed and the recognised dish that stays. Showing this third
  /// name made the warning ("looks more like X") contradict the keep button
  /// ("Keep Y").
  String? _observedFoodName;

  /// The name the tourist typed, kept only to render the mismatch warning
  /// ("this photo doesn't look like `<typed>`") when Gemini could not
  /// confirm it against the photo. A mismatched typed name can NEVER become
  /// the recognised dish - the tourist must keep the detected food instead -
  /// so no details for it are held.
  String? _typedName;

  XFile? get capturedImage => _capturedImage;
  LocalFood? get recognizedFood => _recognizedFood;
  List<LocalFood> get multipleResults => _multipleResults;
  String? get recognitionError => _recognitionError;
  bool get isProcessing => _isProcessing;
  bool get hasMultipleResults => _multipleResults.length > 1;
  bool get isLocalFood => _isLocalFood;

  /// Whether the recognised food fits the catalogue's dish types - see
  /// [_fitsCatalogueCategory].
  bool get fitsCatalogueCategory => _fitsCatalogueCategory;
  double get priceMin => _priceMin;
  double get priceMax => _priceMax;
  List<String> get dietaryRestrictions => _dietaryRestrictions;

  /// The VARIANT name the recognised food was actually seen/typed as when it
  /// EXTENDS the dictionary dish into an unlisted variant (`Cendol Jagung` ->
  /// `Cendol`) - shown on the result card and carried onto
  /// `landmark_item.variant`. Empty when the name IS the dish.
  String get variant => _variant;

  /// Whether the recognised food conflicts with the signed-in tourist's
  /// dietary restrictions - the result card shows a warning (adding is still
  /// allowed).
  bool get hasDietaryConflict => _dietaryConflicts.isNotEmpty;

  /// The user's restriction names this food conflicts with (their wording).
  List<String> get dietaryConflicts => _dietaryConflicts;
  double get confidence => _confidence;
  bool get nameMismatch => _nameMismatch;
  String? get observedFoodName => _observedFoodName;

  /// The name the tourist typed, kept for the mismatch warning while Gemini
  /// has not confirmed it; null when there is nothing pending.
  String? get typedName => _typedName;

  /// Whether the current recognition is shaky enough to ask the tourist to
  /// verify it. The threshold itself is a domain rule and lives in
  /// `FoodRecognitionLogic.isLowConfidence` - this getter just surfaces the
  /// already-decided answer so the View never compares numbers itself.
  bool get isLowConfidence => landmarkLogic.isLowConfidence(_confidence);

  /// Whether the current fix makes "Add New Landmark" impossible (A9) - a
  /// new landmark may only be added on Malaysian land, so a fix at sea or
  /// outside Malaysia blocks it. `false` when there is no fix yet (nothing to
  /// judge against).
  bool get isAddLandmarkBlockedByLocation =>
      _currentLocation.isKnown &&
      !landmarkLogic.isOnLand(
        _currentLocation.latitude,
        _currentLocation.longitude,
      );

  /// Why "Add New Landmark" is unavailable for the current spot - shown on
  /// the result card in place of the add prompt. Null when the location
  /// allows adding.
  String? get addLandmarkLocationBlockMessage =>
      isAddLandmarkBlockedByLocation ? _offLandAddMessage : null;

  static const String _offLandAddMessage =
      'New landmarks can only be added on Malaysian land - you are at sea or '
      'outside Malaysia, so a landmark cannot be added here.';

  /// Keeps [isProcessing] true until [minimumLoadingDuration] has elapsed
  /// since [startedAt]. The result is already stored by the time this runs -
  /// the loading state simply stays up so the card does not appear (and the
  /// tourist cannot act on it) until the data has had time to render.
  Future<void> _holdLoadingUntil(DateTime startedAt) async {
    final Duration elapsed = DateTime.now().difference(startedAt);
    final Duration remaining = minimumLoadingDuration - elapsed;
    if (remaining > Duration.zero) {
      await Future<void>.delayed(remaining);
    }
  }

  /// Loads the signed-in tourist's dietary restrictions once, so
  /// [hasDietaryConflict] can warn as soon as a dish is recognised. Failures
  /// degrade to "no restrictions" (no warning) rather than blocking capture.
  /// On a fresh-capture push it also loads any saved incomplete submissions,
  /// so the View can remind the tourist where one can be continued.
  @override
  Future<void> onInit() async {
    locationFacade.register(this);
    _userDietaryRestrictions = await landmarkLogic.userDietaryRestrictions();
    _recomputeDietaryConflicts();
    if (_purpose == FoodRecognitionPurpose.food) {
      try {
        _pendingDrafts = await landmarkLogic.pendingLandmarkDrafts();
      } catch (_) {
        // A failed draft read must never block capturing a new food.
        _pendingDrafts = const <LandmarkDraft>[];
      }
    }
    safeNotifyListeners();
  }

  /// Continues [draft] - hands it to `AddLandmarkView` and opens the form
  /// pre-filled. Called by [proceedToAddLandmark] when the same dish at the
  /// same spot matches a saved draft, so a repeated capture continues that
  /// visit instead of stacking a second draft of it. (Continuing from the
  /// Incomplete Submissions list is that screen's own ViewModel's job.)
  void openDraft(LandmarkDraft draft) {
    LandmarkDraftHandoff().pendingDraft = draft;
    AppNavigator.push(AppRoutes.addLandmark);
  }

  /// Re-evaluates the same-restaurant rule for the just-taken capture:
  /// an additional food / signboard / stall more than 50 m from where the
  /// first food was captured cannot belong to this landmark. [capturedWhat]
  /// names the rejected capture in the message ("This food", ...).
  void _evaluateCaptureRange(String capturedWhat) {
    _captureRangeError =
        landmarkLogic.isSameRestaurantCaptureRange(
          _referenceLocation,
          _captureLocation,
        )
        ? null
        : landmarkLogic.captureTooFarMessage(capturedWhat);
  }

  /// Why "Add to Landmark" is withheld for the recognised food: it is
  /// ALREADY on the form this capture returns to - the same duplicate rule
  /// the form itself applies (`LandmarkSubmissionLogic.isSameDishAndVariant`,
  /// synonyms and all), checked HERE so the button is never offered for a
  /// dish that would only be rejected after popping back. Null otherwise -
  /// and always for the primary flow, which has no form yet.
  String? get duplicateFormFoodBlockMessage {
    if (_purpose != FoodRecognitionPurpose.additionalFood) return null;
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

  /// Re-derives [_dietaryConflicts] from the current food tags and the user's
  /// saved restrictions - call whenever either side changes.
  void _recomputeDietaryConflicts() {
    _dietaryConflicts = landmarkLogic.dietaryConflicts(
      userRestrictions: _userDietaryRestrictions,
      foodTags: _dietaryRestrictions,
    );
  }

  @override
  void dispose() {
    locationFacade.unregister(this);
    super.dispose();
  }

  /// REQ106_1 - ask for the OS camera permission before the View opens the
  /// camera preview. The View calls this instead of a shared client; the
  /// request travels ViewModel -> facade -> logic -> repository -> device.
  Future<bool> requestCameraPermission() =>
      landmarkLogic.requestCameraPermission();

  /// Capture image and send to Gemini for recognition (REQ106_1, REQ106_2).
  /// Used for both [FoodRecognitionPurpose.food] and
  /// [FoodRecognitionPurpose.additionalFood] - only what happens after
  /// success differs (see [proceedToAddLandmark] vs [confirmFoodAndReturn]).
  /// Errors: A2 (timeout), A3 (not local food), A4 (no food), A18 (incomplete)
  Future<void> captureAndRecognize(XFile image) async {
    _isProcessing = true;
    _recognitionError = null;
    _recognizedFood = null;
    _multipleResults = [];
    // Freeze where the tourist is AT CAPTURE TIME - the landmark is located
    // here (not where they happen to be when they tap "Add New Landmark"),
    // and this is the spot later captures are measured against.
    _captureLocation = _currentLocation;
    _captureRangeError = null;
    notifyListeners();
    // Loading floor: Gemini may return fast, but the result card must not
    // appear (and look half-rendered) before the data has had time to
    // settle - see [minimumLoadingDuration].
    final DateTime startedAt = DateTime.now();

    try {
      _capturedImage = image;
      final List<int> bytes = await image.readAsBytes();
      final FoodRecognitionResult result = await landmarkLogic.recognizeFood(
        bytes,
      );
      _isLocalFood = result.isLocalFood;
      _fitsCatalogueCategory = result.fitsCatalogueCategory;
      _priceMin = result.priceMin;
      _priceMax = result.priceMax;
      _confidence = result.confidence;
      _dietaryRestrictions = result.dietaryRestrictions;
      _variant = result.variant;
      _recomputeDietaryConflicts();
      if (result.candidates.length > 1) {
        // Gemini was unsure between a few likely dishes (A5) - show the
        // top-3 picker instead of a single result.
        _recognizedFood = null;
        _multipleResults = result.candidates;
      } else {
        _recognizedFood = result.candidates.first;
        _multipleResults = [];
      }
      // 50 m same-restaurant rule: an additional food captured far from
      // where the first food was captured cannot join the same landmark.
      _evaluateCaptureRange('This food');
      // Result is stored but isProcessing stays true until the floor is met.
      await _holdLoadingUntil(startedAt);
      notifyListeners();
    } catch (e) {
      // Errors surface immediately - the floor is for settling SUCCESS data,
      // not for holding a failure message hostage.
      _recognitionError = _humaniseError(e);
      notifyListeners();
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// Handle multiple results - user selects one (A5). The picked candidate
  /// may be name-only (a picker candidate that isn't in the catalogue - see
  /// `FoodRecognitionLogic._nameOnlyFood`), so its FULL details are fetched
  /// - the catalogue record if there is one, else a full Gemini analysis of
  /// the picked name + the captured photo (via `resolveByName`) - before the
  /// single-result card settles. This is what fills the result card and
  /// "View Details" (and the suggested price range) for the picked dish;
  /// without it a non-catalogue pick would show only its name.
  /// The picked food is set immediately so the picker closes; the loading
  /// state then stays up through the enrichment (plus the [minimumLoadingDuration]
  /// floor) so the sparse name-only pick is never shown as the settled answer.
  Future<void> selectFromMultiple(LocalFood food) async {
    _recognizedFood = food;
    _multipleResults = [];
    // A picker is only ever shown for a Malaysian local food that fits a
    // catalogue dish type - keep both flags consistent with the photo that
    // produced these candidates. The price range is filled once the full
    // analysis resolves below.
    _isLocalFood = true;
    _fitsCatalogueCategory = true;
    _priceMin = 0;
    _priceMax = 0;
    _confidence = 1.0; // The tourist chose - treat the pick as certain.
    notifyListeners();

    final XFile? image = _capturedImage;
    if (image == null) return; // No photo to enrich with - keep the pick.
    final DateTime startedAt = DateTime.now();
    _isProcessing = true;
    notifyListeners();
    try {
      final List<int> bytes = await image.readAsBytes();
      final resolved = await landmarkLogic.enrichCandidate(bytes, food.name);
      _recognizedFood = resolved.food;
      _priceMin = resolved.priceMin;
      _priceMax = resolved.priceMax;
      _dietaryRestrictions = resolved.dietaryRestrictions;
      _variant = resolved.variant;
      _recomputeDietaryConflicts();
      _fitsCatalogueCategory = resolved.fitsCatalogueCategory;
      await _holdLoadingUntil(startedAt);
      notifyListeners();
    } catch (_) {
      // Gemini/catalogue hiccup - keep the picked (possibly name-only) food
      // rather than dropping the selection. The tourist can retry via the
      // manual name entry.
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// Hard input cap for the manual "type the food name" fields - the View
  /// passes it to their TextField maxLength (see
  /// `LandmarkSubmissionLogic.maxFoodNameLength`).
  int get foodNameMaxLength => landmarkLogic.maxFoodNameLength;

  /// Amber warning while the typed food name gets long (from 45 characters).
  /// A domain rule in the logic layer, so the single-result and
  /// multiple-results entry fields always show the same message.
  String? foodNameWarning(String name) =>
      landmarkLogic.foodNameLengthWarning(name);

  /// Manual fallback: the tourist types the food name when Gemini's
  /// candidates don't include the right dish (see
  /// `FoodRecognitionLogic.resolveByName`). When Gemini confirms the typed
  /// name matches the photo, the single-result card shows it. When it does
  /// NOT match, the detected food is kept, a "this doesn't look like
  /// `<typed name>`" warning is shown, and the typed name can NOT be added -
  /// the tourist can only keep the detected food (see [dismissNameMismatch]).
  Future<void> enterFoodName(String name) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return;
    _isProcessing = true;
    _recognitionError = null;
    notifyListeners();
    // Same loading floor as [captureAndRecognize] - the manually-resolved
    // card must not appear before its data has had time to settle.
    final DateTime startedAt = DateTime.now();
    try {
      final XFile? image = _capturedImage;
      if (image == null) {
        _recognitionError = 'No captured photo to analyse - capture one first.';
      } else {
        final List<int> bytes = await image.readAsBytes();
        final resolved = await landmarkLogic.resolveByName(bytes, trimmed);
        _multipleResults = [];
        if (resolved.nameMatchesPhoto) {
          // Gemini confirms the typed name IS what the photo shows - use it.
          _recognizedFood = resolved.food;
          _priceMin = resolved.priceMin;
          _priceMax = resolved.priceMax;
          _isLocalFood = resolved.isLocalFood;
          _fitsCatalogueCategory = resolved.fitsCatalogueCategory;
          _confidence = resolved.matchConfidence;
          _dietaryRestrictions = resolved.dietaryRestrictions;
          _variant = resolved.variant;
          _recomputeDietaryConflicts();
          _nameMismatch = false;
          _observedFoodName = null;
          _typedName = null;
        } else {
          // Gemini can't confirm the typed name - the detected food stays
          // and the tourist is told the typed dish can't be added. The typed
          // name is NOT applied under any circumstances: a photo that
          // doesn't show a dish must never become that dish.
          _nameMismatch = true;
          _observedFoodName = resolved.observedFood;
          _typedName = trimmed;
        }
        await _holdLoadingUntil(startedAt);
      }
      notifyListeners();
    } catch (e) {
      _recognitionError = _humaniseError(e);
      notifyListeners();
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// "Add New Landmark" - hands the recognized food (and its photo) to
  /// `AddLandmarkView` and navigates straight to the form. Primary entry
  /// point only ([FoodRecognitionPurpose.food]).
  ///
  /// Before opening a FRESH form the VIEW first asks whether this capture
  /// should continue a saved draft instead - see [draftToContinue], which
  /// the View calls (after the "Before you start" reminder) and turns into
  /// the "continue your unfinished submission?" prompt.
  Future<void> proceedToAddLandmark() async {
    final LocalFood? food = _recognizedFood;
    if (food == null) return;
    // A non-local food, or a Malaysian product that isn't a catalogue dish
    // type (snack/package/canned drink), is never allowed to become a
    // landmark - the UI hides the button, this guard is the second line of
    // defence.
    if (!_isLocalFood || !_fitsCatalogueCategory) return;
    // A new landmark may only be added on Malaysian land (A9) - while the fix
    // is at sea / outside Malaysia the UI hides the button and this guard is
    // the second line of defence.
    if (isAddLandmarkBlockedByLocation) return;
    // A capture rejected by the same-restaurant range check (50 m) must not
    // reach the form - the UI withholds the button, this guard backs it up.
    if (isCaptureOutOfRange) return;
    LandmarkDraftHandoff().pushAddLandmark(
      food,
      _capturedImage,
      isLocalFood: _isLocalFood,
      fitsCatalogueCategory: _fitsCatalogueCategory,
      priceMin: _priceMin,
      priceMax: _priceMax,
      confidence: _confidence,
      dietaryRestrictions: _dietaryRestrictions,
      dietaryConflicts: _dietaryConflicts,
      variant: _variant,
      captureLocation: _captureLocation,
    );
  }

  /// The saved submission the current capture could CONTINUE, or null -
  /// always a FRESH drafts read (the list [onInit] loaded can be stale by
  /// now), matched by the SAME dish + variant + the capture spot (50 m). The
  /// View calls this after the "Before you start" reminder and asks the
  /// tourist "continue your unfinished submission?" when it returns a draft;
  /// a failed read returns null (a fresh form is always a safe fallback).
  Future<LandmarkDraft?> draftToContinue() async {
    final LocalFood? food = _recognizedFood;
    if (food == null) return null;
    try {
      final List<LandmarkDraft> drafts = await landmarkLogic
          .pendingLandmarkDrafts();
      _pendingDrafts = drafts;
      safeNotifyListeners();
      return landmarkLogic.matchingLandmarkDraft(
        drafts: drafts,
        food: food,
        captureLocation: _captureLocation,
        variant: _variant,
      );
    } catch (_) {
      // Best-effort: without the records, open a fresh form.
      return null;
    }
  }

  /// Re-reads the saved incomplete submissions for the reminder notice - the
  /// list [onInit] loaded can be stale by the time the tourist is back on
  /// this screen (a form may have been saved or discarded since). A failed
  /// read keeps the previous list: naming a possibly-stale draft beats
  /// showing no notice at all.
  Future<void> refreshPendingDrafts() async {
    try {
      _pendingDrafts = await landmarkLogic.pendingLandmarkDrafts();
      safeNotifyListeners();
    } catch (_) {
      // Best-effort - see above.
    }
  }

  /// "View Details" (A6) - hands the recognized food (and its photo) to the
  /// food-detail screen before navigating there. For the primary entry point
  /// ([FoodRecognitionPurpose.food]) the detail screen's confirm goes on to a
  /// fresh `AddLandmarkView`; for [FoodRecognitionPurpose.additionalFood] it
  /// marks the hand-off so the detail screen returns the food to the *existing*
  /// form instead (see
  /// `LandmarkDraftHandoff.pendingReturnToFormAsAdditionalFood`).
  ///
  /// The first food's capture spot ([_referenceLocation]) rides along, so the
  /// detail screen re-checks the 50 m same-restaurant rule before this food
  /// may join a landmark - a capture this screen blocked must stay blocked
  /// there too. The form's own dishes ([_existingFormFoods]) ride along for
  /// the same reason: the duplicate rule is re-checked there as well.
  void proceedToViewDetails() {
    final LocalFood? food = _recognizedFood;
    if (food == null) return;
    if (_purpose == FoodRecognitionPurpose.additionalFood) {
      LandmarkDraftHandoff().pendingReturnToFormAsAdditionalFood = true;
    }
    LandmarkDraftHandoff().pushLandmarkDetail(
      food,
      _capturedImage,
      isLocalFood: _isLocalFood,
      fitsCatalogueCategory: _fitsCatalogueCategory,
      priceMin: _priceMin,
      priceMax: _priceMax,
      confidence: _confidence,
      dietaryRestrictions: _dietaryRestrictions,
      dietaryConflicts: _dietaryConflicts,
      variant: _variant,
      captureLocation: _captureLocation,
      referenceLocation: _referenceLocation,
      existingFormFoods: _existingFormFoods,
    );
  }

  /// "Add to Landmark" (A12) - pops the recognized food (and its photo)
  /// back to the `AddLandmarkView` that pushed this screen. Only for
  /// [FoodRecognitionPurpose.additionalFood].
  void confirmFoodAndReturn() {
    final LocalFood? food = _recognizedFood;
    final XFile? image = _capturedImage;
    if (food == null ||
        image == null ||
        _purpose != FoodRecognitionPurpose.additionalFood) {
      return;
    }
    // A non-local food - or a Malaysian product that isn't a catalogue dish
    // type - is never allowed back onto a landmark draft either.
    if (!_isLocalFood || !_fitsCatalogueCategory) return;
    // Captured too far from the first food (50 m) - not the same restaurant,
    // so it must never join the form (the UI tells the tourist to capture
    // again on site; this guard backs that up).
    if (isCaptureOutOfRange) return;
    if (_hasReturned) return;
    _hasReturned = true;
    AppNavigator.pop<AdditionalFoodCaptureResult>((
      food: food,
      image: image,
      priceMin: _priceMin,
      priceMax: _priceMax,
      captureLocation: _captureLocation,
      variant: _variant,
      dietaryRestrictions: _dietaryRestrictions,
    ));
  }

  /// "Keep the detected food" - the ONLY action on a mismatch warning. The
  /// typed name (which Gemini could not confirm against the photo) is
  /// discarded; what Gemini identified stays.
  void dismissNameMismatch() {
    if (!_nameMismatch) return;
    _nameMismatch = false;
    _observedFoodName = null;
    _typedName = null;
    notifyListeners();
  }

  /// Clear and retry
  void clearAndRetry() {
    _capturedImage = null;
    _recognizedFood = null;
    _multipleResults = [];
    _recognitionError = null;
    _isLocalFood = true;
    _fitsCatalogueCategory = true;
    _priceMin = 0;
    _priceMax = 0;
    _dietaryRestrictions = const <String>[];
    _dietaryConflicts = const <String>[];
    _variant = '';
    _nameMismatch = false;
    _observedFoodName = null;
    _typedName = null;
    _extractedRestaurantName = null;
    // The next capture takes its own fix and is checked again.
    _captureRangeError = null;
    _captureLocation = TouristLocation.unknown;
    notifyListeners();
  }

  // --- SIGNBOARD / STALL CAPTURE (this screen reused, purpose != food) ---

  String? _extractedRestaurantName; // Only set after a signboard capture

  String? get extractedRestaurantName => _extractedRestaurantName;

  /// Capture and analyze a restaurant signboard photo (A17, A19).
  /// Validity (frame completeness, text extracted) is checked in
  /// `LandmarkSubmissionLogic.analyzeSignboard`, which throws on failure -
  /// this just catches and humanises, same pattern as [captureAndRecognize].
  /// Errors: A2 (timeout), A7 (no text), A19 (incomplete frame)
  Future<void> captureSignboard(XFile image) async {
    _isProcessing = true;
    _recognitionError = null;
    // The signboard photo's own location - compared with the first food's
    // location (50 m rule) before the photo may join the landmark.
    _captureLocation = _currentLocation;
    _captureRangeError = null;
    notifyListeners();

    try {
      final List<int> bytes = await image.readAsBytes();
      final String restaurantName = await landmarkLogic.analyzeSignboard(bytes);
      _capturedImage = image;
      _extractedRestaurantName = restaurantName;
      _evaluateCaptureRange('This signboard photo');
    } catch (e) {
      _recognitionError = _humaniseError(e);
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// Capture and analyze a stall photo (A17). Verifies the frame is complete
  /// - does NOT auto-fill anything. Validity is checked in
  /// `LandmarkSubmissionLogic.analyzeStall`, which throws on failure - see
  /// [captureSignboard]'s doc for why this moved out of the ViewModel.
  /// Errors: A2 (timeout), A8 (not detected), A15 (incomplete frame)
  Future<void> captureStallImage(XFile image) async {
    _isProcessing = true;
    _recognitionError = null;
    // The stall photo's own location - compared with the first food's
    // location (50 m rule) before the photo may join the landmark.
    _captureLocation = _currentLocation;
    _captureRangeError = null;
    notifyListeners();

    try {
      final List<int> bytes = await image.readAsBytes();
      await landmarkLogic.analyzeStall(bytes);
      _capturedImage = image;
      _evaluateCaptureRange('This stall photo');
    } catch (e) {
      _recognitionError = _humaniseError(e);
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// Confirms the signboard/stall capture and pops back to `AddLandmarkView`
  /// with the result. Only for [FoodRecognitionPurpose.signboard] /
  /// [FoodRecognitionPurpose.stall], once a capture has succeeded.
  void confirmCaptureAndReturn() {
    final XFile? image = _capturedImage;
    if (image == null) return;
    if (_purpose != FoodRecognitionPurpose.signboard &&
        _purpose != FoodRecognitionPurpose.stall) {
      return;
    }
    // A signboard/stall photo taken more than 50 m from the first food's
    // location is not this restaurant's - the UI withholds "Confirm" and
    // asks for a new capture; this guard backs it up.
    if (isCaptureOutOfRange) return;
    if (_hasReturned) return;
    _hasReturned = true;

    AppNavigator.pop<LandmarkImageCaptureResult>((
      image: image,
      imageType: _purpose == FoodRecognitionPurpose.signboard
          ? 'signboard'
          : 'stall',
      extractedRestaurantName: _extractedRestaurantName,
      captureLocation: _captureLocation,
    ));
  }

  String _humaniseError(Object error) {
    final String raw = error.toString();
    // Gemini quota / rate-limit (HTTP 429, RESOURCE_EXHAUSTED) - the free
    // tier can be temporarily exhausted. Show a friendly "unavailable"
    // message instead of dumping the raw error body on screen.
    if (raw.contains('429') ||
        raw.toLowerCase().contains('quota') ||
        raw.contains('RESOURCE_EXHAUSTED')) {
      return 'This feature is currently unavailable. Please try again later.';
    }
    return raw.startsWith('Exception: ')
        ? raw.substring('Exception: '.length)
        : 'Service taking too long. Please try again.';
  }
}
