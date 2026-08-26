import 'package:image_picker/image_picker.dart';
import 'package:meta/meta.dart' show visibleForTesting;

import '../app/routing/app_navigator.dart';
import '../app/routing/app_routes.dart';
import '../core/base_view_model.dart';
import '../domain_model/food_recognition_result.dart';
import '../domain_model/local_food.dart';
import '../model/business_logic/landmark_logic_facade.dart';

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

  /// Gemini's suggested MYR price range for [pendingRecognizedFood], carried
  /// onto the submitted `LandmarkItem`. `0` means unknown.
  double pendingPriceMin = 0;
  double pendingPriceMax = 0;

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

  /// Stashes [food] and [image] for the food-detail screen
  /// (`LandmarkDetailView`, at `AppRoutes.landmarkDetail`) and
  /// navigates there - the one shared implementation of "go view details
  /// for this recognized food". `FoodRecognitionViewModel.proceedToViewDetails`
  /// and `AddLandmarkViewModel.viewFoodDetails` both call this rather than
  /// each re-implementing the hand-off + navigation themselves - they're two
  /// different ViewModel instances (different screens, no DI between them,
  /// and the original camera-screen instance may not even still exist by
  /// the time `AddLandmarkView` is reached via "View Details"), so each
  /// still needs its own thin entry point - but the actual 2-line body only
  /// lives here once.
  void pushLandmarkDetail(
    LocalFood food,
    XFile? image, {
    bool isLocalFood = true,
    double priceMin = 0,
    double priceMax = 0,
  }) {
    pendingRecognizedFood = food;
    pendingCapturedImage = image;
    pendingIsLocalFood = isLocalFood;
    pendingPriceMin = priceMin;
    pendingPriceMax = priceMax;
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
    double priceMin = 0,
    double priceMax = 0,
  }) {
    pendingRecognizedFood = food;
    pendingCapturedImage = image;
    pendingIsLocalFood = isLocalFood;
    pendingPriceMin = priceMin;
    pendingPriceMax = priceMax;
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
    pendingPriceMin = 0;
    pendingPriceMax = 0;
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
});

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
class FoodRecognitionViewModel extends BaseViewModel {
  FoodRecognitionViewModel({
    @visibleForTesting LandmarkLogicFacade? landmarkLogic,
  }) : landmarkLogic = landmarkLogic ?? LandmarkLogicFacade();

  final LandmarkLogicFacade landmarkLogic;

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

  /// Whether the recognised food is Malaysian local food. When false the
  /// result is still shown (and "View Details" works) but the tourist must
  /// not be allowed to add it as a landmark.
  bool _isLocalFood = true;

  /// Gemini's suggested MYR price range for the recognised food - carried
  /// onto the submitted `LandmarkItem` (see `FoodRecognitionResult`).
  double _priceMin = 0;
  double _priceMax = 0;

  /// Gemini's confidence (0..1) in the recognised food - surfaced in the UI
  /// so a shaky result is never presented as certain. For manual name entry
  /// this is the name-vs-photo verification confidence, so a name Gemini
  /// can't confirm comes back low and the low-confidence cue fires. `1.0`
  /// when unknown (picker selection - the tourist chose).
  double _confidence = 1.0;

  /// Whether a manually-typed name was verified against the photo and found
  /// NOT to match it (with decent confidence) - the card warns "this photo
  /// doesn't look like X" and the tourist can keep their name anyway
  /// (warn-and-allow).
  bool _nameMismatch = false;

  /// What the photo actually shows, in Gemini's words, when [_nameMismatch].
  String? _observedFoodName;

  /// The typed-name result held for explicit confirmation - set when Gemini
  /// could not confirm the typed name against the photo but the tourist may
  /// still want it anyway (see [acceptTypedName]).
  ({
    LocalFood food,
    double priceMin,
    double priceMax,
    bool isLocalFood,
    double confidence,
  })? _pendingTyped;

  XFile? get capturedImage => _capturedImage;
  LocalFood? get recognizedFood => _recognizedFood;
  List<LocalFood> get multipleResults => _multipleResults;
  String? get recognitionError => _recognitionError;
  bool get isProcessing => _isProcessing;
  bool get hasMultipleResults => _multipleResults.length > 1;
  bool get isLocalFood => _isLocalFood;
  double get priceMin => _priceMin;
  double get priceMax => _priceMax;
  double get confidence => _confidence;
  bool get nameMismatch => _nameMismatch;
  String? get observedFoodName => _observedFoodName;

  /// The name the tourist typed, kept for the mismatch warning while Gemini
  /// has not confirmed it; null when there is nothing pending.
  String? get typedName => _pendingTyped?.food.name;

  /// Whether the current recognition is shaky enough to ask the tourist to
  /// verify it. The threshold itself is a domain rule and lives in
  /// `FoodRecognitionLogic.isLowConfidence` - this getter just surfaces the
  /// already-decided answer so the View never compares numbers itself.
  bool get isLowConfidence => landmarkLogic.isLowConfidence(_confidence);

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
    notifyListeners();

    try {
      _capturedImage = image;
      final List<int> bytes = await image.readAsBytes();
      final FoodRecognitionResult result = await landmarkLogic.recognizeFood(
        bytes,
      );
      _isLocalFood = result.isLocalFood;
      _priceMin = result.priceMin;
      _priceMax = result.priceMax;
      _confidence = result.confidence;
      if (result.candidates.length > 1) {
        // Gemini was unsure between a few likely dishes (A5) - show the
        // top-3 picker instead of a single result.
        _recognizedFood = null;
        _multipleResults = result.candidates;
      } else {
        _recognizedFood = result.candidates.first;
        _multipleResults = [];
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

  /// Handle multiple results - user selects one (A5). The picked candidate
  /// may be name-only (a picker candidate that isn't in the catalogue - see
  /// `FoodRecognitionLogic._nameOnlyFood`), so its FULL details are fetched
  /// - the catalogue record if there is one, else a full Gemini analysis of
  /// the picked name + the captured photo (via `resolveByName`) - before the
  /// single-result card settles. This is what fills the result card and
  /// "View Details" (and the suggested price range) for the picked dish;
  /// without it a non-catalogue pick would show only its name.
  /// The picked food is set immediately so the picker closes; the enrichment
  /// then swaps in the full record when it arrives.
  Future<void> selectFromMultiple(LocalFood food) async {
    _recognizedFood = food;
    _multipleResults = [];
    // A picker is only ever shown for a Malaysian local food - keep the flag
    // consistent with the photo that produced these candidates. The price
    // range is filled once the full analysis resolves below.
    _isLocalFood = true;
    _priceMin = 0;
    _priceMax = 0;
    _confidence = 1.0; // The tourist chose - treat the pick as certain.
    notifyListeners();

    final XFile? image = _capturedImage;
    if (image == null) return; // No photo to enrich with - keep the pick.
    try {
      final List<int> bytes = await image.readAsBytes();
      final resolved = await landmarkLogic.enrichCandidate(bytes, food.name);
      _recognizedFood = resolved.food;
      _priceMin = resolved.priceMin;
      _priceMax = resolved.priceMax;
      notifyListeners();
    } catch (_) {
      // Gemini/catalogue hiccup - keep the picked (possibly name-only) food
      // rather than dropping the selection. The tourist can retry via the
      // manual name entry.
    }
  }

  /// Manual fallback: the tourist types the food name when Gemini's
  /// candidates don't include the right dish (see
  /// `FoodRecognitionLogic.resolveByName`). When Gemini confirms the typed
  /// name matches the photo, the single-result card shows it. When it does
  /// NOT match, the detected food is kept and a mismatch warning is shown -
  /// the typed name is only applied if the tourist explicitly confirms via
  /// [acceptTypedName].
  Future<void> enterFoodName(String name) async {
    final String trimmed = name.trim();
    if (trimmed.isEmpty) return;
    _isProcessing = true;
    _recognitionError = null;
    notifyListeners();
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
          _confidence = resolved.matchConfidence;
          _nameMismatch = false;
          _observedFoodName = null;
          _pendingTyped = null;
        } else {
          // Gemini can't confirm the typed name - KEEP the detected food and
          // warn, instead of silently renaming it. The typed name is only
          // applied if the tourist explicitly confirms via [acceptTypedName].
          _nameMismatch = true;
          _observedFoodName = resolved.observedFood;
          _pendingTyped = (
            food: resolved.food,
            priceMin: resolved.priceMin,
            priceMax: resolved.priceMax,
            isLocalFood: resolved.isLocalFood,
            confidence: resolved.matchConfidence,
          );
        }
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
  void proceedToAddLandmark() {
    final LocalFood? food = _recognizedFood;
    if (food == null) return;
    // A non-local food is never allowed to become a landmark - the UI hides
    // the button, this guard is the second line of defence.
    if (!_isLocalFood) return;
    LandmarkDraftHandoff().pushAddLandmark(
      food,
      _capturedImage,
      isLocalFood: _isLocalFood,
      priceMin: _priceMin,
      priceMax: _priceMax,
    );
  }

  /// "View Details" (A6) - hands the recognized food (and its photo) to the
  /// food-detail screen before navigating there. For the primary entry point
  /// ([FoodRecognitionPurpose.food]) the detail screen's confirm goes on to a
  /// fresh `AddLandmarkView`; for [FoodRecognitionPurpose.additionalFood] it
  /// marks the hand-off so the detail screen returns the food to the *existing*
  /// form instead (see
  /// `LandmarkDraftHandoff.pendingReturnToFormAsAdditionalFood`).
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
      priceMin: _priceMin,
      priceMax: _priceMax,
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
    // A non-local food is never allowed back onto a landmark draft either.
    if (!_isLocalFood) return;
    AppNavigator.pop<AdditionalFoodCaptureResult>((
      food: food,
      image: image,
      priceMin: _priceMin,
      priceMax: _priceMax,
    ));
  }

  /// "Keep the detected food" - dismisses the mismatch warning and keeps
  /// what Gemini identified; the typed name is discarded (warn-and-allow).
  void dismissNameMismatch() {
    if (!_nameMismatch) return;
    _nameMismatch = false;
    _observedFoodName = null;
    _pendingTyped = null;
    notifyListeners();
  }

  /// "Add as `<typed name>` anyway" - the tourist explicitly confirms they
  /// want the typed name even though Gemini could not confirm it against the
  /// photo. Only now are the food details swapped to what Gemini returned
  /// for that name (the warn-and-allow commit point - the displayed name
  /// never changes without this explicit choice).
  void acceptTypedName() {
    final pending = _pendingTyped;
    if (pending == null) return;
    _recognizedFood = pending.food;
    _priceMin = pending.priceMin;
    _priceMax = pending.priceMax;
    _isLocalFood = pending.isLocalFood;
    _confidence = pending.confidence;
    _nameMismatch = false;
    _observedFoodName = null;
    _pendingTyped = null;
    notifyListeners();
  }

  /// Clear and retry
  void clearAndRetry() {
    _capturedImage = null;
    _recognizedFood = null;
    _multipleResults = [];
    _recognitionError = null;
    _isLocalFood = true;
    _priceMin = 0;
    _priceMax = 0;
    _nameMismatch = false;
    _observedFoodName = null;
    _pendingTyped = null;
    _extractedRestaurantName = null;
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
    notifyListeners();

    try {
      final List<int> bytes = await image.readAsBytes();
      final String restaurantName = await landmarkLogic.analyzeSignboard(bytes);
      _capturedImage = image;
      _extractedRestaurantName = restaurantName;
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
    notifyListeners();

    try {
      final List<int> bytes = await image.readAsBytes();
      await landmarkLogic.analyzeStall(bytes);
      _capturedImage = image;
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

    AppNavigator.pop<LandmarkImageCaptureResult>((
      image: image,
      imageType: _purpose == FoodRecognitionPurpose.signboard
          ? 'signboard'
          : 'stall',
      extractedRestaurantName: _extractedRestaurantName,
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
