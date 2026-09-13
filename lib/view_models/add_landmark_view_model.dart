import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../app/routing/app_navigator.dart';
import '../app/routing/app_routes.dart';
import '../core/base_view_model.dart';
import '../domain_model/address_suggestion.dart';
import '../domain_model/landmark_draft.dart';
import '../domain_model/local_food.dart';
import '../domain_model/opening_hour.dart';
import '../domain_model/place_overwrite_report.dart';
import '../domain_model/similar_place_candidate.dart';
import '../domain_model/submitted_landmark.dart';
import '../domain_model/tourist_location.dart';
import '../model/business_logic/landmark_logic_facade.dart';
import 'current_location_facade.dart';
import 'food_recognition_view_model.dart'
    show
        AdditionalFoodCaptureResult,
        ExistingFormFood,
        FoodRecognitionPurpose,
        LandmarkDraftHandoff,
        LandmarkImageCaptureResult;

/// One food attached to the landmark being submitted, paired with the price
/// the tourist enters for it.
///
/// `LandmarkItem.price` lives on the item, not on the landmark - a stall can
/// sell two dishes at two different prices under one landmark, so price is
/// tracked per food here too, not as a single field on this ViewModel.
///
/// [entryId] is this form entry's own identity - NOT `food.id`. A freshly
/// recognized `LocalFood` always has `id: 0` until it is saved (see
/// `FoodRecognitionViewModel`), so two unsaved foods added to the same draft
/// would collide if keyed by `food.id`. [entryId] stays unique for the life
/// of the form even while every food on it still has `id: 0`.
class LandmarkFoodEntry {
  LandmarkFoodEntry._({
    required this.entryId,
    required this.food,
    this.image,
    this.photoRef,
    this.price,
    this.priceMin = 0,
    this.priceMax = 0,
    this.captureLocation = TouristLocation.unknown,
    this.variant = '',
    this.dietaryRestrictions = const <String>[],
  });

  /// Creates a new form entry with a fresh, form-local identity.
  factory LandmarkFoodEntry.newEntry({
    required LocalFood food,
    XFile? image,
    LandmarkDraftPhoto? photoRef,
    double? price,
    double priceMin = 0,
    double priceMax = 0,
    TouristLocation captureLocation = TouristLocation.unknown,
    String variant = '',
    List<String> dietaryRestrictions = const <String>[],
  }) => LandmarkFoodEntry._(
    entryId: _nextEntryId++,
    food: food,
    image: image,
    photoRef: photoRef,
    price: price,
    priceMin: priceMin,
    priceMax: priceMax,
    captureLocation: captureLocation,
    variant: variant,
    dietaryRestrictions: dietaryRestrictions,
  );

  static int _nextEntryId = 0;

  final int entryId;
  final LocalFood food;

  /// This food's own photo, as captured on `FoodRecognitionView` - only
  /// ever set for additional foods (see `AddLandmarkViewModel.addAdditionalFood`).
  /// The primary food's photo is tracked separately, via
  /// `AddLandmarkViewModel._recognizedFoodImage` - not duplicated here.
  final XFile? image;

  /// The stored form of this food's photo (see [image]) - set when a draft
  /// is resumed, so submission reuses the uploaded object instead of
  /// re-uploading. Null while only a local capture exists.
  final LandmarkDraftPhoto? photoRef;
  final double? price;

  /// Gemini's suggested MYR price range for this food, carried onto the
  /// persisted `LandmarkItem`. `0` means unknown.
  final double priceMin;
  final double priceMax;

  /// Where this food's photo was captured (see the 50 m same-restaurant
  /// rule) - only meaningful for additional foods; the primary food's spot
  /// lives on the ViewModel itself.
  final TouristLocation captureLocation;

  /// The VARIANT name this food was seen/typed as, when it EXTENDS the
  /// dictionary dish into an unlisted variant (`Cendol Jagung` -> curated
  /// `Cendol`) - written to `landmark_item.variant`. Empty when the name IS
  /// the dish.
  final String variant;

  /// Canonical dietary-restriction names that apply to THIS food - written
  /// to `landmark_item.dietary_restrictions` (one comma-joined text column).
  final List<String> dietaryRestrictions;

  LandmarkFoodEntry withPrice(double newPrice) => LandmarkFoodEntry._(
    entryId: entryId,
    food: food,
    image: image,
    photoRef: photoRef,
    price: newPrice,
    priceMin: priceMin,
    priceMax: priceMax,
    captureLocation: captureLocation,
    variant: variant,
    dietaryRestrictions: dietaryRestrictions,
  );

  LandmarkFoodEntry withFood(LocalFood newFood) => LandmarkFoodEntry._(
    entryId: entryId,
    food: newFood,
    image: image,
    photoRef: photoRef,
    price: price,
    priceMin: priceMin,
    priceMax: priceMax,
    captureLocation: captureLocation,
    variant: variant,
    dietaryRestrictions: dietaryRestrictions,
  );

  LandmarkFoodEntry withPriceRange({
    required double priceMin,
    required double priceMax,
  }) => LandmarkFoodEntry._(
    entryId: entryId,
    food: food,
    image: image,
    photoRef: photoRef,
    price: price,
    priceMin: priceMin,
    priceMax: priceMax,
    captureLocation: captureLocation,
    variant: variant,
    dietaryRestrictions: dietaryRestrictions,
  );

  /// The observed/typed VARIANT name for this food - see [variant].
  LandmarkFoodEntry withVariant(String newVariant) => LandmarkFoodEntry._(
    entryId: entryId,
    food: food,
    image: image,
    photoRef: photoRef,
    price: price,
    priceMin: priceMin,
    priceMax: priceMax,
    captureLocation: captureLocation,
    variant: newVariant,
    dietaryRestrictions: dietaryRestrictions,
  );

  /// After this entry's local photo was uploaded while saving a draft - the
  /// stored reference replaces nothing (the local file is kept for preview
  /// until submission).
  LandmarkFoodEntry withPhotoRef(LandmarkDraftPhoto ref) => LandmarkFoodEntry._(
    entryId: entryId,
    food: food,
    image: image,
    photoRef: ref,
    price: price,
    priceMin: priceMin,
    priceMax: priceMax,
    captureLocation: captureLocation,
    variant: variant,
    dietaryRestrictions: dietaryRestrictions,
  );
}

/// ViewModel for `AddLandmarkView`.
///
/// Submit a new food landmark with dual image capture (signboard OR stall,
/// captured via `FoodRecognitionView` reused in that mode - see
/// [openSignboardCapture]/[openStallCapture]). Manages form state, location,
/// per-food pricing, operating hours, and submission.
///
/// Implements [CurrentLocationListener] so a background process can
/// push updates in through an inbound ViewModel facade. Register in `onInit`,
/// unregister in `dispose` - forgetting the second leaks this object.
///
/// Rules this class follows (see `lib/core/base_view_model.dart`):
///   * no `package:flutter/material.dart` import and no `BuildContext`;
///   * it knows the logic facade(s) below and nothing else - never a
///     repository, never a shared client, never Supabase or Gemini;
///   * state goes in private fields with read-only getters; commands wrap their
///     facade call in `runGuarded` so busy and error states behave the same on
///     every screen.
///
/// Two different cross-screen data patterns are used here, deliberately:
///   * data flowing IN from a screen that pushed this one (the recognized
///     food) arrives through `LandmarkDraftHandoff`, read by the View and set
///     via [setRecognizedFood] BEFORE [onInit] runs - see that class's doc;
///   * data flowing BACK from a screen this ViewModel pushes (the signboard /
///     stall capture) rides the `Future<T?>` result of `AppNavigator.push<T>`
///     directly - see [openSignboardCapture]/[openStallCapture].
class AddLandmarkViewModel extends BaseViewModel
    implements CurrentLocationListener {
  /// [websiteReachability] is a test seam for the live website-link probe
  /// (see [setRestaurantWebsite]) - it defaults to the logic facade's
  /// network check; tests inject a stub so the field's check state can be
  /// exercised without touching the network.
  AddLandmarkViewModel({Future<bool> Function(String url)? websiteReachability})
    : _websiteReachability = websiteReachability;

  /// Creates the logic facade below - a seam the ViewModel tests override to
  /// hand in a fake, so no test ever reaches Supabase/Gemini.
  @protected
  LandmarkLogicFacade createLandmarkLogic() => LandmarkLogicFacade();

  late final LandmarkLogicFacade landmarkLogic = createLandmarkLogic();

  final Future<bool> Function(String url)? _websiteReachability;

  /// Inbound: `LocationMonitor` publishes here.
  final CurrentLocationFacade locationFacade = CurrentLocationFacade();

  @override
  Future<void> onInit() async {
    locationFacade.register(this);
  }

  // --- LOCATION STATE ---
  TouristLocation _currentLocation = TouristLocation.unknown;
  TouristLocation _adjustedLocation = TouristLocation.unknown;

  /// Where the FIRST food was captured - the landmark's location (the pin
  /// defaults here, and a hand-moved pin may only stray 100 m from it).
  /// Set from `LandmarkDraftHandoff` before `onInit()`, or from a resumed
  /// draft. [TouristLocation.unknown] when the capture carried no fix - the
  /// live fix is used instead, see [baseLocation].
  TouristLocation _captureLocation = TouristLocation.unknown;

  /// Pushed by `LocationMonitor` through [CurrentLocationFacade].
  @override
  void onCurrentLocationChanged(TouristLocation location) {
    _currentLocation = location;
    // A capture the 50 m rule rejected names the spot it was captured at
    // ([_captureRejected]): a LATER fix means the tourist has moved - or a
    // dev GPS mock was stopped - so that verdict no longer describes where
    // they are and must not keep sitting under the Submit bar.
    if (_captureRejected && location.isKnown) {
      _submitError = null;
      _captureRejected = false;
    }
    // The address may still be waiting for its first fix (a name-typed food
    // carries no capture spot). Fill it as soon as a fix arrives - unless it
    // was typed or already filled.
    if (_address.trim().isEmpty && _mapDerivedAddress == null) {
      _scheduleMapAddressLookup();
    }
    safeNotifyListeners();
  }

  /// Whether [submitError] is the 50 m capture rejection from
  /// [_acceptCaptureLocation] rather than a field/submit problem - see
  /// [onCurrentLocationChanged].
  bool _captureRejected = false;

  /// Drops the 50 m capture rejection, if that is what [submitError] holds:
  /// it described one capture at one spot, and the attempt that produced it
  /// is over (a new capture is starting, or the fix has moved on).
  void _clearCaptureRejection() {
    if (!_captureRejected) return;
    _captureRejected = false;
    _submitError = null;
  }

  String? _locationError;

  // --- ADDRESS ↔ MAP BINDING (OpenStreetMap) ---

  /// True when the current address text came FROM the map (a pin move or a
  /// selected suggestion). Only then may a later pin move replace it; the
  /// moment the tourist types, the text is theirs and map changes leave it
  /// alone - the two may legitimately disagree (OpenStreetMap does not know
  /// every address), and [canApplyMapAddress] offers the map's version back.
  bool _addressFromMap = false;
  bool get addressFromMap => _addressFromMap;

  /// Bumped by every PROGRAMMATIC address change (map fill, suggestion pick,
  /// "use the map pin's address"). `AddLandmarkView` watches this to force
  /// its text field to show the new text - the same pattern as the
  /// signboard name's extraction version.
  int _addressVersion = 0;
  int get addressVersion => _addressVersion;

  /// The last composed address the pinned spot produced - offered by
  /// [canApplyMapAddress] and applied by [applyMapAddressFromPin].
  String? _mapDerivedAddress;

  /// True while the pin's reverse lookup runs.
  bool _mapAddressLookupRunning = false;
  bool get isLookingUpMapAddress => _mapAddressLookupRunning;

  /// True when the last pin lookup failed or OpenStreetMap has no address
  /// there. Shown as an inline notice; it never blocks anything.
  bool _mapAddressUnavailable = false;
  bool get mapAddressUnavailable => _mapAddressUnavailable;

  Timer? _mapAddressDebounce;

  /// The spot of a just-picked suggestion while its own reverse lookup runs:
  /// the lookup may refresh the map's copy of the address, but must not
  /// overwrite the text the tourist picked.
  TouristLocation? _keepSelectedAddressFor;

  /// Live OpenStreetMap suggestions for the address field, nearest first.
  List<AddressSuggestion> _addressSuggestions = const <AddressSuggestion>[];
  List<AddressSuggestion> get addressSuggestions => _addressSuggestions;

  /// True while a suggestion search runs.
  bool _addressSearchRunning = false;
  bool get isSearchingAddress => _addressSearchRunning;

  /// True when the search could not run at all (offline / rate-limited).
  bool _addressSearchUnavailable = false;
  bool get addressSearchUnavailable => _addressSearchUnavailable;

  /// True when a completed search matched nothing.
  bool _addressSearchEmpty = false;
  bool get addressSearchEmpty => _addressSearchEmpty;

  Timer? _addressSearchDebounce;

  /// Guards against out-of-order search responses: only the newest query's
  /// answer may populate the list.
  int _addressSearchToken = 0;

  /// The warning shown after picking a suggestion farther than the pin may
  /// move (100 m): the address text is kept, the pin stays put, submission
  /// remains allowed.
  String? _addressPinWarning;
  String? get addressPinWarning => _addressPinWarning;

  // --- FOOD STATE (auto-filled from recognition; price entered per food) ---
  LandmarkFoodEntry? _primaryFood;

  /// Soft price guidance from Gemini's suggested range - set in
  /// [setPrimaryFoodPrice], shown under the primary food's price field.
  String? _primaryFoodPriceWarning;

  /// The primary food's own photo (as captured on `FoodRecognitionView`),
  /// carried here via `LandmarkDraftHandoff.pendingCapturedImage` so the
  /// "Recognised Food" card can show the same thumbnail the tourist saw
  /// there - see [setRecognizedFoodImage].
  XFile? _recognizedFoodImage;

  /// The stored version of [_recognizedFoodImage] - set when a draft is
  /// resumed, so the card can show the photo and submission can reuse the
  /// uploaded object instead of re-uploading it.
  LandmarkDraftPhoto? _recognizedFoodImageRef;

  /// Gemini's confidence in the recognized primary dish's name, carried from
  /// the recognition screen through `LandmarkDraftHandoff` - the catalogue-
  /// growth gate (`FoodRecognitionLogic.registerNewDishes`) demands a high
  /// bar before writing a new `local_food` row.
  double _recognizedFoodConfidence = 0;

  /// Dietary restrictions (canonical names) for the recognized primary dish,
  /// carried via `LandmarkDraftHandoff` - written to the
  /// `food_dietary_restriction` association table when it becomes a new
  /// catalogue row.
  List<String> _recognizedFoodDietaryRestrictions = const <String>[];

  /// The VARIANT name the primary food was seen/typed as when it EXTENDS the
  /// dictionary dish into an unlisted variant (`Cendol Jagung` -> `Cendol`) -
  /// written to the submitted `landmark_item.variant`; empty when the name IS
  /// the dish. Carried from `LandmarkDraftHandoff`.
  String _recognizedFoodVariant = '';

  /// The signed-in tourist's restrictions the recognized primary dish
  /// conflicts with - shown as a warning on its card (adding is still
  /// allowed). Carried from `LandmarkDraftHandoff`.
  List<String> _recognizedFoodDietaryConflicts = const <String>[];
  List<LandmarkFoodEntry> _additionalFoods = <LandmarkFoodEntry>[];

  /// Per-entry soft price guidance, keyed by the form-local
  /// [LandmarkFoodEntry.entryId].
  final Map<int, String> _additionalFoodPriceWarnings = <int, String>{};

  // --- IMAGE CAPTURE STATE (MANDATORY - ONE of two) ---
  XFile? _capturedImage; // Either signboard or stall
  String? _capturedImageType; // 'signboard' or 'stall'
  bool _isSignboardDisabled = false; // True after stall captured
  bool _isStallDisabled = false; // True after signboard captured

  /// Where the signboard/stall photo was taken - its OWN fix, kept separately
  /// from the first food's [_captureLocation]. `unknown` until a photo is
  /// captured, and dropped with it (see [clearCapturedImage]).
  TouristLocation _capturedImageLocation = TouristLocation.unknown;

  /// The stored version of [_capturedImage] (object name + URL + type) -
  /// set when a draft is resumed, so the preview can render it and
  /// submission reuses the uploaded object.
  LandmarkDraftPhoto? _capturedImageRef;

  // --- FORM STATE ---
  String _restaurantName = '';

  /// Optional contact/address for the place (validated when provided): a
  /// Malaysian phone number, an http(s) website, and a free-text address.
  /// The phone field shows a fixed "+60" and edits the national digits; the
  /// STORED value is the national format the `restaurant` table uses - see
  /// [setRestaurantPhone].
  String _phone = '';

  String _website = '';
  String _address = '';

  /// Live website-link probe state - see [setRestaurantWebsite]. The probe
  /// waits for typing to pause ([websiteLinkCheckDelay]).
  Timer? _websiteLinkDebounce;
  bool _websiteLinkChecking = false;
  bool _websiteLinkUnreachable = false;

  /// How long typing must pause before the website link is probed.
  static const Duration websiteLinkCheckDelay = Duration(milliseconds: 700);

  /// Bumped by [setExtractedRestaurantName] whenever a signboard capture
  /// overwrites [_restaurantName]. `AddLandmarkView` compares this to the
  /// version it last applied to its text field to tell a fresh signboard
  /// result (which must overwrite the tourist's typed name) apart from the
  /// tourist's own typing (which must not fight the field).
  int _extractedRestaurantNameVersion = 0;

  /// The name Gemini read off the signboard THIS form captured (see
  /// [setExtractedRestaurantName]) - the baseline [hasEditedSignboardName]
  /// compares the field against. Null while no signboard reading belongs to
  /// the photo the form is holding: a stall capture, a cancelled photo, or a
  /// resumed draft (a draft stores the photo, not the reading).
  String? _signboardDetectedName;

  /// True when [confirmRestaurant] refused the click because the name the
  /// tourist typed does not match the captured signboard. One-shot: the View
  /// takes it with [takeSignboardNameMismatch] and says so in a dialog.
  bool _signboardNameMismatch = false;

  /// True while a Confirm click is waiting on that same check (a Gemini
  /// call): the Confirm row shows progress and refuses a second click rather
  /// than firing the question twice.
  bool _isConfirming = false;

  /// True while the near-duplicate check is running - the nearby search plus
  /// one photo download + Gemini call per candidate. The View blocks the form
  /// (name and images included) for as long as it is set: nothing on the form
  /// may change while the question about THIS name/photo is being decided.
  bool _isCheckingSimilarPlace = false;

  /// The nearby place whose stored photo Gemini judged to be the SAME
  /// restaurant as this form's capture - the "did you mean this restaurant?"
  /// question, waiting for the tourist's answer. Null when there is none.
  SimilarPlaceCandidate? _similarPlacePrompt;

  /// The form's dishes the chosen place ALREADY lists (see
  /// [acceptSimilarPlace]) - what the acknowledgement must name before they
  /// are dropped from this submission.
  List<String> _existingDishNames = const <String>[];

  /// True when EVERY dish this form holds already exists at the chosen place:
  /// nothing would be written, so the form leaves for the dashboard instead of
  /// submitting (see [finishAsAlreadyThere]).
  bool _allDishesExist = false;

  /// Every weekday always has at least one row here. A Closed/Unknown day
  /// has exactly one row (times null); an Open day can have more than one
  /// - matching the real `OpeningHours` table directly, where each row is
  /// independently `(day, status, opening_time, closing_time)`, not a
  /// day-level wrapper around a list.
  ///
  /// Defaults to [DayStatus.unknown], not [DayStatus.closed] - a tourist
  /// submitting a new landmark typically only knows it was open at the
  /// moment they were standing there, not its full weekly schedule.
  /// Defaulting to "closed" made an active (and usually false) claim that
  /// the place is shut every day; "unknown" honestly says "we don't have
  /// this information yet," which is exactly what that status exists for.
  Map<Weekday, List<OpeningHour>> _operatingHours =
      <Weekday, List<OpeningHour>>{
        for (final Weekday day in Weekday.values)
          day: <OpeningHour>[
            OpeningHour(id: 0, day: day, status: DayStatus.unknown),
          ],
      };

  // --- DRAFT (INCOMPLETE SUBMISSION) STATE ---
  /// The saved draft row this form is updating; `0` while it has never been
  /// saved. Saving again UPDATES the same row instead of piling up a new
  /// draft every time the app goes to the background.
  int _draftId = 0;
  int get draftId => _draftId;

  /// The rows of drafts that were COMBINED into this form (see
  /// [mergeExistingDraft]). They are removed once this form is saved - or
  /// once it is submitted - so the restaurant keeps ONE submission; until
  /// then their data is safe in case this form is discarded.
  final List<int> _absorbedDraftIds = <int>[];

  /// Whether this form is editing an ALREADY-SAVED incomplete submission
  /// (opened from the Incomplete Submissions list, or auto-continued when
  /// the same dish was captured again). Its Discard
  /// lives on the Incomplete Submissions screen, so the leave dialog does
  /// not offer a second, hidden delete - see `AddLandmarkView._confirmLeave`.
  bool get hasSavedDraft => _draftId != 0;

  /// True while a draft save (photo uploads + row write) is running, so the
  /// lifecycle hook and the back-button flow can never start two
  /// overlapping saves.
  bool _draftSaving = false;
  bool get isSavingDraft => _draftSaving;

  /// Set when an "Add More Food" result was REJECTED because the same dish
  /// (same variant) is already on this form - the View shows a snackbar and
  /// clears it via [takeDuplicateFoodNotice].
  bool _duplicateFoodRejected = false;

  bool takeDuplicateFoodNotice() {
    final bool rejected = _duplicateFoodRejected;
    _duplicateFoodRejected = false;
    return rejected;
  }

  // --- SUBMISSION STATE ---
  bool _isSubmitting = false;
  String? _submitError;

  /// The sign-in requirement - copy this ViewModel authors itself, so the
  /// submit-failure mapper may pass it through verbatim.
  static const String _signInRequiredMessage = 'Sign in to submit a landmark.';

  /// True when the last submit MERGED the dishes into an existing place
  /// (catalogue restaurant or submitted landmark, same name within ~100m)
  /// instead of creating a new landmark - see `LandmarkSubmitResult`.
  bool _submitMerged = false;
  String? _submitTargetName;
  List<String> _submitAddedDishNames = const <String>[];
  List<String> _submitExistingDishNames = const <String>[];

  // --- GETTERS ---
  TouristLocation get currentLocation => _currentLocation;
  TouristLocation get adjustedLocation => _adjustedLocation;
  String? get locationError => _locationError;

  /// Where the first food was captured. See [_captureLocation].
  TouristLocation get captureLocation => _captureLocation;

  /// The landmark's own location: the first food's capture spot when there
  /// is one, else the live fix (e.g. a name-typed food with no GPS fix at
  /// capture time). The pin starts here and submission uses this spot.
  TouristLocation get baseLocation =>
      _captureLocation.isKnown ? _captureLocation : _currentLocation;

  /// Whether the current fix makes adding a landmark impossible (A9) - a new
  /// landmark may only be submitted on Malaysian land, so a fix at sea or
  /// outside Malaysia blocks the form. `false` when there is no fix yet
  /// (nothing to judge against). Judged at the EFFECTIVE landmark location
  /// (a hand-moved pin, else the captured/gps spot).
  bool get isAddLocationBlocked {
    final TouristLocation location = _adjustedLocation.isKnown
        ? _adjustedLocation
        : baseLocation;
    return location.isKnown &&
        !landmarkLogic.isOnLand(location.latitude, location.longitude);
  }

  /// The pin's correction allowance in metres (A9.1) - drawn around the map
  /// fix and quoted in the "address is too far from the pin" warning.
  double get pinRangeMetres => landmarkLogic.pinAdjustmentRangeMetres;

  /// Why the form is blocked for the current spot - shown on the Location
  /// card and as the disabled-Submit reason. Null when the location allows
  /// adding.
  String? get addLocationBlockMessage =>
      isAddLocationBlocked ? _offLandAddMessage : null;

  static const String _offLandAddMessage =
      'New landmarks can only be added on Malaysian land - you are at sea or '
      'outside Malaysia, so no landmark can be submitted here.';

  LocalFood? get recognizedFood => _primaryFood?.food;

  /// The VARIANT name the primary food was seen/typed as when it EXTENDS the
  /// dictionary dish into an unlisted variant (`Cendol Jagung` -> `Cendol`) -
  /// shown on its card and written to `landmark_item.variant`. Empty when the
  /// name IS the dish.
  String get recognizedFoodVariant => _recognizedFoodVariant;

  XFile? get recognizedFoodImage => _recognizedFoodImage;
  double? get primaryFoodPrice => _primaryFood?.price;
  String? get primaryFoodPriceWarning => _primaryFoodPriceWarning;

  /// Gemini's suggested price range for the primary food as a display line
  /// ("Suggested price: RM 4.50 - RM 8.50"), shown under its price field
  /// whenever it is known - even while the typed value is invalid. Null when
  /// no range is known.
  String? get primaryFoodSuggestedPriceText => _primaryFood == null
      ? null
      : landmarkLogic.suggestedPriceRangeText(
          _primaryFood!.priceMin,
          _primaryFood!.priceMax,
        );

  /// The form's complete price rule set - the inclusive band, the field's
  /// digit shape, and the two TEXT rules (the leading-zero rewrite while
  /// typing and the two-decimal format once the field is left). Handed to
  /// every price field so the field, the submit checks and the report flow
  /// can never disagree; the rules themselves live in
  /// `LandmarkSubmissionLogic`.
  ({
    double minPrice,
    double maxPrice,
    int integralDigits,
    int decimalDigits,
    String rangeText,
    String Function(String text) normaliseEntryText,
    String Function(String text) formatEntryText,
  })
  get priceRules => (
    minPrice: landmarkLogic.minPrice,
    maxPrice: landmarkLogic.maxPrice,
    integralDigits: landmarkLogic.priceIntegralDigits,
    decimalDigits: landmarkLogic.priceDecimalDigits,
    rangeText: landmarkLogic.priceBandRangeText,
    normaliseEntryText: landmarkLogic.normalisePriceEntryText,
    formatEntryText: landmarkLogic.formatPriceText,
  );

  /// The restrictions the recognized primary dish conflicts with - see
  /// `_recognizedFoodDietaryConflicts`.
  List<String> get primaryFoodDietaryConflicts =>
      _recognizedFoodDietaryConflicts;
  String? additionalFoodPriceWarning(int entryId) =>
      _additionalFoodPriceWarnings[entryId];

  /// Gemini's suggested price range for one additional food - see
  /// [primaryFoodSuggestedPriceText].
  String? additionalFoodSuggestedPriceText(int entryId) {
    for (final LandmarkFoodEntry entry in _additionalFoods) {
      if (entry.entryId == entryId) {
        return landmarkLogic.suggestedPriceRangeText(
          entry.priceMin,
          entry.priceMax,
        );
      }
    }
    return null;
  }

  List<LandmarkFoodEntry> get additionalFoods =>
      List<LandmarkFoodEntry>.unmodifiable(_additionalFoods);

  XFile? get capturedImage => _capturedImage;
  String? get capturedImageType => _capturedImageType;

  /// Where the signboard/stall photo itself was taken - its OWN fix, separate
  /// from the first food's [captureLocation]; the second food keeps its own
  /// on [LandmarkFoodEntry.captureLocation]. `unknown` until a photo is
  /// captured (restored with a resumed draft's stored photo, which carries
  /// its own spot), and cleared with the photo.
  TouristLocation get capturedImageLocation => _capturedImageLocation;

  /// Whether the form's mandatory signboard/stall photo exists - either
  /// captured on this device or carried over from a resumed draft.
  bool get hasImageCaptured =>
      _capturedImage != null || _capturedImageRef != null;
  bool get isSignboardDisabled => _isSignboardDisabled;
  bool get isStallDisabled => _isStallDisabled;

  /// Stored URL of the landmark's own signboard/stall photo - set when this
  /// form was resumed from a draft (in which case [capturedImage] is null
  /// and the photo lives in storage). Null when no photo exists yet.
  String? get capturedImageUrl => _capturedImageRef?.url;

  /// Stored URL of the primary food's photo - set when this form was resumed
  /// from a draft (see [capturedImageUrl]).
  String? get recognizedFoodImageUrl => _recognizedFoodImageRef?.url;

  String get restaurantName => _restaurantName;

  /// See [_extractedRestaurantNameVersion].
  int get extractedRestaurantNameVersion => _extractedRestaurantNameVersion;

  /// The name Gemini read off the captured signboard, or null when the photo
  /// brought no reading of its own (stall capture, cancelled photo, resumed
  /// draft). See [_signboardDetectedName].
  String? get signboardDetectedName => _signboardDetectedName;

  /// Whether the tourist replaced Gemini's signboard reading with a name of
  /// their own - the case [confirmRestaurant] sends back to the signboard
  /// for a second opinion. False when there is no reading to differ from.
  bool get hasEditedSignboardName {
    final String? detected = _signboardDetectedName;
    return detected != null && _restaurantName.trim() != detected.trim();
  }

  /// True while a Confirm click is waiting on the signboard-name check - see
  /// [confirmRestaurant]. The Confirm row shows progress while it is set.
  bool get isConfirming => _isConfirming;

  /// True while the near-duplicate check runs - see [_isCheckingSimilarPlace].
  /// The View blocks the form (name and images included) while it is set.
  bool get isCheckingSimilarPlace => _isCheckingSimilarPlace;

  /// See [_similarPlacePrompt]. The View asks the question while it is
  /// non-null: a nearby place whose stored photo looks like this form's
  /// capture, under a name that only LOOKS similar.
  SimilarPlaceCandidate? get similarPlacePrompt => _similarPlacePrompt;

  /// The form's dishes the chosen place already lists - see
  /// [_existingDishNames].
  List<String> get existingDishNames => _existingDishNames;

  /// True when every dish on this form is already listed at the chosen place
  /// - see [_allDishesExist].
  bool get allDishesExist => _allDishesExist;

  /// The same-place details a merge would replace, waiting for the tourist's
  /// answer - see [checkDetailsOverwrite] / [resolveOverwrite]. Non-null only
  /// while the question is outstanding.
  PlaceOverwriteReport? _overwritePrompt;

  /// See [_overwritePrompt].
  PlaceOverwriteReport? get overwritePrompt => _overwritePrompt;

  /// The tourist's answer: true = write this form's details over the stored
  /// ones, false = leave the stored record completely untouched. Null while
  /// unanswered - and a merge then keeps the stored record (the safe way).
  bool? _overwriteExistingDetails;

  /// See [_overwriteExistingDetails].
  bool? get overwriteExistingDetails => _overwriteExistingDetails;

  /// The relevant values the answer was given for (see [_detailsSignature]):
  /// editing any of them after answering asks again.
  String? _overwriteAnsweredFor;

  /// Whether this form carries anything a same-place merge could overwrite:
  /// a contact detail, or hours for at least one day.
  bool get hasDetailsToMerge =>
      _phone.trim().isNotEmpty ||
      _website.trim().isNotEmpty ||
      _address.trim().isNotEmpty ||
      _operatingHours.values.any(
        (List<OpeningHour> rows) =>
            rows.any((OpeningHour row) => row.status != DayStatus.unknown),
      );

  /// Whether the same place already stores details this form would REPLACE -
  /// true when the question is now pending: the View shows
  /// [overwritePrompt] and calls [resolveOverwrite]. False when there is
  /// nothing to ask (no relevant entry, no same-place record, nothing would
  /// change, or the tourist already answered for these exact values).
  ///
  /// Asked at Confirm and again just before the write (see
  /// [submitLandmark]): the merge is otherwise silent, and a curated phone
  /// number, address or set of hours must not vanish without the tourist
  /// saying so.
  Future<bool> checkDetailsOverwrite() async {
    if (!hasDetailsToMerge) return false;
    if (_overwriteAnsweredFor == _detailsSignature) return false;
    final TouristLocation location = _adjustedLocation.isKnown
        ? _adjustedLocation
        : baseLocation;
    try {
      final PlaceOverwriteReport? report = await landmarkLogic
          .mergeOverwriteReport(
            restaurantName: _restaurantName,
            latitude: location.isKnown ? location.latitude : null,
            longitude: location.isKnown ? location.longitude : null,
            phone: _phone,
            website: _website,
            address: _address,
            operatingHours: _operatingHours,
          );
      if (report == null) {
        // Nothing would be replaced - remember that for these values so the
        // submit path does not ask again.
        _overwriteExistingDetails = false;
        _overwriteAnsweredFor = _detailsSignature;
        return false;
      }
      _overwritePrompt = report;
      safeNotifyListeners();
      return true;
    } catch (_) {
      // Unreadable stored details: no question, and the merge then keeps the
      // stored record.
      return false;
    }
  }

  /// The tourist's answer to [overwritePrompt].
  void resolveOverwrite(bool overwrite) {
    if (_overwritePrompt == null) return;
    _overwritePrompt = null;
    _overwriteExistingDetails = overwrite;
    _overwriteAnsweredFor = _detailsSignature;
    safeNotifyListeners();
  }

  /// The values the details question is about, as one comparable string - an
  /// edit after answering changes it, so the question is asked again.
  String get _detailsSignature {
    final TouristLocation location = _adjustedLocation.isKnown
        ? _adjustedLocation
        : baseLocation;
    final List<String> days = <String>[
      for (final Weekday day in Weekday.values)
        for (final OpeningHour row
            in _operatingHours[day] ?? const <OpeningHour>[])
          '${row.status.name}:${row.opensAt ?? -1}-${row.closesAt ?? -1}',
    ];
    return <String>[
      _phone.trim(),
      _website.trim(),
      _address.trim(),
      location.isKnown ? location.latitude.toStringAsFixed(5) : '',
      location.isKnown ? location.longitude.toStringAsFixed(5) : '',
      days.join(','),
    ].join('|');
  }

  String get restaurantPhone => _phone;
  String get restaurantWebsite => _website;
  String get restaurantAddress => _address;

  /// The fixed country-code prefix the phone field shows as plain text
  /// beside it - it is never part of the field's editable text.
  String get phoneCountryCode => landmarkLogic.phoneCountryCode;

  /// What the phone field's editable text holds: the national digits of
  /// [restaurantPhone] ("012-684 0922" reads back as "126840922" - the
  /// fixed "+60" replaces the trunk "0").
  String get restaurantPhoneLocal => landmarkLogic.phoneNationalPart(_phone);

  /// Field caps exposed to the View (TextField maxLength).
  int get restaurantNameMaxLength => landmarkLogic.maxRestaurantNameLength;
  int get phoneMaxLength => landmarkLogic.maxPhoneLength;

  /// The phone field's editable (national) part is capped so the fixed
  /// "+60 " prefix plus the part still fit [phoneMaxLength].
  int get phoneLocalMaxLength =>
      landmarkLogic.maxPhoneLength - phoneCountryCode.length - 1;

  int get websiteMaxLength => landmarkLogic.maxWebsiteLength;
  int get addressMaxLength => landmarkLogic.maxAddressLength;

  /// Required-name error (empty / invalid characters / hard limit reached).
  ///
  /// Plain wording on purpose: the tourist is told their input is invalid or
  /// too long - never which character class or internal rule rejected it.
  String? get restaurantNameError {
    if (_restaurantName.isEmpty) return 'Restaurant name is required.';
    if (landmarkLogic.containsControlCharacters(_restaurantName) ||
        !landmarkLogic.isValidRestaurantNameText(_restaurantName)) {
      return 'Invalid restaurant name.';
    }
    if (_restaurantName.length >= landmarkLogic.maxRestaurantNameLength) {
      return 'Restaurant name is too long.';
    }
    return null;
  }

  /// Amber warning once the name is close to its cap (91-99 characters) -
  /// typing continues to the cap and a name AT the cap can still be
  /// submitted. Advisory only, exactly like the website/address "stay
  /// under" warnings (this one used to gate submission at 30 characters).
  String? get restaurantNameWarning {
    final int length = _restaurantName.length;
    final int maxLength = landmarkLogic.maxRestaurantNameLength;
    if (length >= landmarkLogic.restaurantNameWarnFromLength &&
        length < maxLength) {
      return 'Restaurant name should stay under $maxLength characters '
          '(currently $length).';
    }
    return null;
  }

  /// Optional-field errors - null when the field is empty (allowed) or valid.
  ///
  /// ONE plain message for every phone failure - a control character or a
  /// number that is not a Malaysian mobile/landline both read as "that is
  /// not a phone number", with the expected shape shown as an example.
  String? get restaurantPhoneError {
    if (_phone.isEmpty) return null;
    if (landmarkLogic.containsControlCharacters(_phone) ||
        !landmarkLogic.isValidMalaysianPhone(_phone)) {
      return 'Enter a valid Malaysian mobile or landline, e.g. 012-345 6789.';
    }
    return null;
  }

  /// Optional website. STRICT (RFC 3986 + XSS rules - see
  /// `LandmarkSubmissionLogic.isValidWebsiteFormat`): exactly ONE full
  /// http(s) link with no spaces and no markup, on a real dotted domain -
  /// and at most [maxWebsiteLength] characters. Every SHAPE failure
  /// (characters, spaces, more than one link, malformed) reports the same
  /// plain message; only "too long" is called out separately.
  String? get restaurantWebsiteError {
    if (_website.isEmpty) return null;
    if (landmarkLogic.containsControlCharacters(_website) ||
        landmarkLogic.websiteContainsWhitespace(_website) ||
        landmarkLogic.websiteContainsMultipleUrls(_website) ||
        !landmarkLogic.isValidWebsiteFormat(_website)) {
      return 'Invalid website link, e.g. https://example.com.';
    }
    if (_website.length > landmarkLogic.maxWebsiteLength) {
      return 'Website link is too long.';
    }
    return null;
  }

  /// Amber warning once the website is within 5 characters of its 2048 cap
  /// (2043-2048) - typing continues to the cap and a valid link AT the cap
  /// is still submit-able; the warning is advisory only.
  String? get restaurantWebsiteWarning {
    final int length = _website.length;
    if (length >= landmarkLogic.websiteWarnFromLength) {
      return 'Website should stay under '
          '${landmarkLogic.maxWebsiteLength} characters '
          '(currently $length).';
    }
    return null;
  }

  /// True while the debounced website-link probe is running.
  bool get isCheckingWebsiteLink => _websiteLinkChecking;

  /// True when the last probe could not open the link. This DISABLES Submit
  /// (see [canSubmit]) and is what [canSubmitReason] reports; the status line
  /// under the field says the same thing. [submitLandmark] still re-probes
  /// and blocks on its own result, which stays the authority.
  bool get websiteLinkUnreachable => _websiteLinkUnreachable;

  /// The live status line under the website field: "Checking this link…"
  /// while the probe runs, then the unable-to-open note when it failed.
  /// Null while idle or after a successful probe.
  String? get websiteLinkStatus {
    if (_websiteLinkChecking) return 'Checking this link…';
    if (_websiteLinkUnreachable) return _websiteUnreachableMessage;
    return null;
  }

  /// Optional address. The whole judgement - the shape rules (allowed
  /// characters, no leading/trailing or repeated specials, at least one digit
  /// and one letter), the minimum length and the 150 hard stop, in the form's
  /// order and words - is `LandmarkSubmissionLogic.addressError`, ONE rule set
  /// shared with the report page's address field. Every shape violation
  /// reports the same plain "Invalid address."; only the cap is called out
  /// separately.
  String? get restaurantAddressError => landmarkLogic.addressError(_address);

  /// Amber warning while the address is close to its 150 cap (141-149) -
  /// typing continues to the cap; the hard-stop error shows at 150. The
  /// numbers and words are shared with the report page's address field (see
  /// `LandmarkSubmissionLogic.addressLengthWarning`).
  String? get restaurantAddressWarning =>
      landmarkLogic.addressLengthWarning(_address);

  Map<Weekday, List<OpeningHour>> get operatingHours =>
      Map<Weekday, List<OpeningHour>>.unmodifiable(_operatingHours);

  bool get isSubmitting => _isSubmitting;
  String? get submitError => _submitError;

  /// Whether the last successful submit merged into an existing place
  /// instead of creating a new landmark.
  bool get submitMerged => _submitMerged;

  /// Confirmation copy for a MERGED submit (A13) - the place already existed
  /// on the map, so the dishes joined it instead of creating a new pin. Says
  /// which dishes were added and which the place already had, in full
  /// sentences (see `LandmarkSubmissionLogic.mergeConfirmation`). Null when a
  /// new landmark was created (the View shows the default success message
  /// instead). Name lists are capped so an open-ended number of dishes can
  /// never overflow the snackbar.
  String? get submitConfirmation {
    if (!_submitMerged) return null;
    return landmarkLogic.mergeConfirmation(
      targetName: _submitTargetName == null
          ? ''
          : _truncate(_submitTargetName!),
      addedDishNames: _previewNames(_submitAddedDishNames),
      existingDishNames: _previewNames(_submitExistingDishNames),
    );
  }

  /// Caps a dish-name list for the confirmation message - never more than
  /// [_previewNameLimit] names, then a "+N more" tail.
  static const int _previewNameLimit = 3;

  static List<String> _previewNames(List<String> names) {
    if (names.length <= _previewNameLimit) return names;
    return <String>[
      ...names.take(_previewNameLimit),
      '+${names.length - _previewNameLimit} more',
    ];
  }

  /// Truncates long target names so a very long restaurant/landmark name
  /// cannot blow out the snackbar width.
  static String _truncate(String value, {int max = 30}) =>
      value.length <= max ? value : '${value.substring(0, max - 1)}…';

  bool get canSubmit =>
      !isAddLocationBlocked &&
      hasImageCaptured &&
      _restaurantConfirmed &&
      restaurantNameError == null &&
      restaurantPhoneError == null &&
      restaurantWebsiteError == null &&
      // A link the live probe could not open blocks Submit as well - it is
      // the same strict check [submitLandmark] runs, surfaced before the tap
      // instead of after it (see [websiteLinkUnreachable]). Editing the
      // field re-runs the probe, so a fixed link re-enables the button.
      !_websiteLinkUnreachable &&
      restaurantAddressError == null &&
      _primaryFood != null &&
      _primaryFood!.price != null &&
      _additionalFoods.every(
        (LandmarkFoodEntry entry) => entry.price != null,
      ) &&
      _operatingHoursError() == null;

  /// Why [canSubmit] is currently `false` (the first unmet requirement), or
  /// `null` when every requirement is met. Shown under the Submit bar so a
  /// disabled button is never a mystery - previously a greyed-out button
  /// gave no clue which field was actually missing.
  String? get canSubmitReason {
    // At sea / outside Malaysia (A9) - the whole form is blocked no matter
    // what has been filled in.
    if (isAddLocationBlocked) {
      return addLocationBlockMessage;
    }
    if (!hasImageCaptured) {
      return 'Please capture a signboard or stall image.';
    }
    // Empty / invalid / over-long all come from the field's own error, so
    // the reason under the Submit bar can never drift from the field's
    // message.
    final String? nameError = restaurantNameError;
    if (nameError != null) {
      return nameError;
    }
    if (_primaryFood == null) {
      return 'Recognise a food first (capture and add your food)';
    }
    if (_primaryFood!.price == null) {
      return 'Please enter a price for the food';
    }
    for (final LandmarkFoodEntry entry in _additionalFoods) {
      if (entry.price == null) {
        return 'Please enter a price for every added food';
      }
    }
    final String? phoneError = restaurantPhoneError;
    if (phoneError != null) return phoneError;
    final String? websiteError = restaurantWebsiteError;
    if (websiteError != null) return websiteError;
    // The link is well-formed but the live probe could not open it - the
    // button stays disabled until the field is edited (which re-probes).
    if (_websiteLinkUnreachable) return _websiteUnreachableMessage;
    final String? addressError = restaurantAddressError;
    if (addressError != null) return addressError;
    final String? hoursError = _operatingHoursError();
    if (hoursError != null) return hoursError;
    // Checked LAST: everything else being filled in but the tourist never
    // confirmed the restaurant is exactly the case this message is for.
    if (!_restaurantConfirmed) return _confirmRestaurantReason;
    return null;
  }

  /// Shown when the tourist tries to submit without pressing "Confirm" under
  /// the Restaurant Name - they must verify the name first.
  static const String _confirmRestaurantReason =
      'Please press Confirm to check the restaurant name first.';

  /// The ONE sentence for a website link that cannot be opened - shared by
  /// the live status line under the field, the Submit bar's reason and the
  /// submit-time error, so the three can never drift apart.
  static const String _websiteUnreachableMessage =
      "We couldn't open this website. Check the address and try again.";

  // --- COMMANDS ---

  /// Set recognized food (auto-filled from food recognition, or from
  /// `LandmarkDraftHandoff` before `onInit()` - see class doc). Keeps any
  /// price already entered for this food if it is set again. [captureLocation]
  /// is where the food photo was taken - the landmark's location.
  void setRecognizedFood(
    LocalFood food, {
    double priceMin = 0,
    double priceMax = 0,
    double confidence = 0,
    List<String> dietaryRestrictions = const <String>[],
    List<String> dietaryConflicts = const <String>[],
    String variant = '',
    TouristLocation captureLocation = TouristLocation.unknown,
  }) {
    _recognizedFoodConfidence = confidence;
    _recognizedFoodDietaryRestrictions = dietaryRestrictions;
    _recognizedFoodDietaryConflicts = dietaryConflicts;
    _recognizedFoodVariant = variant;
    if (captureLocation.isKnown) _captureLocation = captureLocation;
    _primaryFood = _primaryFood == null
        ? LandmarkFoodEntry.newEntry(
            food: food,
            priceMin: priceMin,
            priceMax: priceMax,
            variant: variant,
          )
        : _primaryFood!
              .withFood(food)
              .withPriceRange(priceMin: priceMin, priceMax: priceMax)
              .withVariant(variant);
    // The previous food's suggested range no longer applies.
    _primaryFoodPriceWarning = null;
    safeNotifyListeners();
  }

  /// Set the primary food's photo - see `_recognizedFoodImage`.
  void setRecognizedFoodImage(XFile image) {
    // Replaces the stored draft photo, if this form was resumed - see
    // setCapturedImage.
    _discardReplacedPhoto(_recognizedFoodImageRef);
    _recognizedFoodImageRef = null;
    _recognizedFoodImage = image;
    safeNotifyListeners();
  }

  /// Best-effort delete of a stored draft photo that a fresh capture just
  /// replaced (or the tourist removed), so the old object does not linger.
  void _discardReplacedPhoto(LandmarkDraftPhoto? ref) {
    if (ref == null) return;
    unawaited(
      landmarkLogic.discardLandmarkDraftPhoto(ref.id).catchError((Object _) {}),
    );
  }

  /// Set the price for the primary (recognized) food. (A16)
  void setPrimaryFoodPrice(double price) {
    if (_primaryFood == null) return;
    if (!landmarkLogic.isValidPrice(price)) {
      _submitError =
          'Price must be between ${landmarkLogic.priceBandRangeText}.';
      safeNotifyListeners();
      return;
    }
    _primaryFood = _primaryFood!.withPrice(price);
    _primaryFoodPriceWarning = landmarkLogic.suggestedPriceWarning(
      _primaryFood!.food.name,
      price,
      _primaryFood!.priceMin,
      _primaryFood!.priceMax,
    );
    _submitError = null;
    safeNotifyListeners();
  }

  /// Adjust map pin location (user drags pin). GPS can be inaccurate, so the
  /// tourist may correct the pin - but only within 100m of the captured fix
  /// (A9.1). Beyond that, the change is rejected and the pin reverts to its
  /// last valid position; nothing here is mutated.
  void adjustLandmarkLocation(double latitude, double longitude) {
    if (!landmarkLogic.isWithinAllowedRange(
      baseLocation,
      latitude,
      longitude,
    )) {
      // M9 - plain wording; the allowance itself lives in `pinRangeMetres`.
      _locationError =
          'The pin can only move ${pinRangeMetres.round()} m from the '
          'captured location.';
      safeNotifyListeners();
      return; // Revert: _adjustedLocation is left unchanged.
    }

    // A new landmark must be on Malaysian land (A9) - the pin can't be
    // dragged out of the country (or into the sea) even within 100m.
    if (!landmarkLogic.isOnLand(latitude, longitude)) {
      _locationError =
          'New landmarks must be within Malaysia and on land.'; // A9
      safeNotifyListeners();
      return;
    }

    _locationError = null;
    _adjustedLocation = TouristLocation(
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: currentLocation.accuracyMeters,
      capturedAt: DateTime.now(),
    );
    // The pin moved: its address follows (or waits on the "use the map
    // pin's address" button when the field was typed by hand).
    _scheduleMapAddressLookup();
    safeNotifyListeners();
  }

  /// Puts the pin back on the first food's captured spot - the "Recover to
  /// captured location" button, shown once the pin has been moved. The
  /// address follows the same rules as any other pin move: a map-sourced
  /// address is refreshed from the captured spot, a hand-typed one stays.
  void resetLandmarkLocation() {
    if (!_adjustedLocation.isKnown) return;
    _adjustedLocation = TouristLocation.unknown;
    _locationError = null;
    _scheduleMapAddressLookup();
    safeNotifyListeners();
  }

  /// Opens `FoodRecognitionView` in signboard-capture mode and waits for its
  /// result. This screen stays on the stack the whole time - the result
  /// comes back through the pushed route's own `Future<T?>`, not a hand-off.
  /// The first food's capture spot is handed over as the reference location,
  /// so the camera can reject a signboard shot taken too far away (50 m
  /// same-restaurant rule); the check is repeated here as a backstop.
  Future<void> openSignboardCapture() async {
    _clearCaptureRejection();
    LandmarkDraftHandoff().pendingPurpose = FoodRecognitionPurpose.signboard;
    LandmarkDraftHandoff().pendingReferenceLocation = baseLocation.isKnown
        ? baseLocation
        : null;
    final LandmarkImageCaptureResult? result =
        await AppNavigator.push<LandmarkImageCaptureResult>(
          AppRoutes.foodRecognition,
        );
    if (result == null) return; // Tourist backed out without confirming.
    // Too far from the first food (50 m): the photo is not this
    // restaurant's - reject it and let them capture again.
    if (!_acceptCaptureLocation(
      result.captureLocation,
      'This signboard photo',
    )) {
      return;
    }

    setCapturedImage(
      result.image,
      result.imageType,
      captureLocation: result.captureLocation,
    );
    if (result.extractedRestaurantName != null) {
      setExtractedRestaurantName(result.extractedRestaurantName);
    }
  }

  /// Same as [openSignboardCapture], in stall-capture mode - no auto-fill.
  Future<void> openStallCapture() async {
    _clearCaptureRejection();
    LandmarkDraftHandoff().pendingPurpose = FoodRecognitionPurpose.stall;
    LandmarkDraftHandoff().pendingReferenceLocation = baseLocation.isKnown
        ? baseLocation
        : null;
    final LandmarkImageCaptureResult? result =
        await AppNavigator.push<LandmarkImageCaptureResult>(
          AppRoutes.foodRecognition,
        );
    if (result == null) return;
    if (!_acceptCaptureLocation(result.captureLocation, 'This stall photo')) {
      return;
    }

    setCapturedImage(
      result.image,
      result.imageType,
      captureLocation: result.captureLocation,
    );
  }

  /// Backstop for the 50 m same-restaurant rule (the camera screen already
  /// blocks such a capture): whether [captured] may join this landmark.
  /// When it is too far from the first food's capture spot, records the
  /// user-facing reason in [submitError] and returns false - the caller
  /// then drops the capture, and the tourist captures again on site.
  bool _acceptCaptureLocation(TouristLocation captured, String capturedWhat) {
    if (landmarkLogic.isSameRestaurantCaptureRange(baseLocation, captured)) {
      return true;
    }
    _submitError = landmarkLogic.captureTooFarMessage(capturedWhat);
    _captureRejected = true;
    safeNotifyListeners();
    return false;
  }

  /// Set captured image (signboard or stall), plus where THAT photo was taken
  /// ([captureLocation] - its own fix, not the first food's).
  /// Automatically disables the other button.
  ///
  /// A NEW photo takes the restaurant confirmation back (see
  /// [confirmRestaurant]): the click is what checked THIS signboard/stall
  /// photo, so replacing the photo - a "Retake", or the other capture mode
  /// after cancelling - makes that click stale even when the restaurant name
  /// itself does not change.
  void setCapturedImage(
    XFile image,
    String imageType, {
    TouristLocation captureLocation = TouristLocation.unknown,
  }) {
    // A fresh capture replaces the stored photo of a resumed draft - the old
    // object is unreferenced from here on, so it is deleted (best-effort).
    _discardReplacedPhoto(_capturedImageRef);
    _capturedImageRef = null;
    _capturedImage = image;
    _capturedImageType = imageType;
    _capturedImageLocation = captureLocation;

    if (imageType == 'signboard') {
      _isStallDisabled = true; // Can't capture stall after signboard
    } else if (imageType == 'stall') {
      _isSignboardDisabled = true; // Can't capture signboard after stall
    }
    // The previous photo's reading goes with the previous photo: the new
    // capture supplies its own (see [setExtractedRestaurantName]), and until
    // it does there is nothing for an edited name to be checked against.
    _signboardDetectedName = null;
    _signboardNameMismatch = false;
    _restaurantConfirmed = false;
    safeNotifyListeners();
  }

  /// Cancels the captured signboard/stall image (the "x" next to it) -
  /// clears it entirely and re-enables both capture buttons. Distinct from
  /// "Retake" (which keeps the mutual-exclusion lock and just re-opens the
  /// same capture mode) - this undoes the choice altogether. Doesn't touch
  /// `_restaurantName` even if it was auto-filled from a signboard - the
  /// tourist may still want to keep that - but DOES take the confirmation
  /// back, because the photo that click checked is now gone.
  void clearCapturedImage() {
    // A stored draft photo is dropped with the capture - never resurrect it
    // on the next save.
    _discardReplacedPhoto(_capturedImageRef);
    _capturedImageRef = null;
    _capturedImage = null;
    _capturedImageType = null;
    _capturedImageLocation = TouristLocation.unknown;
    _isSignboardDisabled = false;
    _isStallDisabled = false;
    _signboardDetectedName = null;
    _signboardNameMismatch = false;
    _restaurantConfirmed = false;
    safeNotifyListeners();
  }

  /// Set extracted restaurant name (from signboard capture only).
  /// Overwrites whatever the tourist typed - the signboard is authoritative,
  /// and they can edit it afterwards. Bumps [_extractedRestaurantNameVersion]
  /// so `AddLandmarkView` can force its text field to show this name even
  /// while the field is still focused (the focus-guarded sync alone would
  /// skip it, leaving the tourist's typed name on screen).
  ///
  /// The reading is kept as [_signboardDetectedName]: an EDIT of it is what
  /// [confirmRestaurant] re-checks against the photo.
  void setExtractedRestaurantName(String? name) {
    if (name != null && name.trim().isNotEmpty) {
      final String next = _clampTo(
        name.trim(),
        landmarkLogic.maxRestaurantNameLength,
      );
      // A NEW signboard name takes the restaurant confirmation back - that
      // click was given for the PREVIOUS name (see [confirmRestaurant]).
      if (next != _restaurantName) _restaurantConfirmed = false;
      _restaurantName = next;
      _signboardDetectedName = next;
      _extractedRestaurantNameVersion++;
      safeNotifyListeners();
    }
  }

  /// Manually set restaurant name (user types). An actual change takes the
  /// restaurant confirmation back - that click checked the PREVIOUS name and
  /// looked up ITS unfinished submissions (see [confirmRestaurant]).
  void setRestaurantName(String name) {
    final String next = _clampTo(
      name.trim(),
      landmarkLogic.maxRestaurantNameLength,
    );
    if (next != _restaurantName) _restaurantConfirmed = false;
    _restaurantName = next;
    safeNotifyListeners();
  }

  /// Whether the tourist confirmed the restaurant details ("Confirm" under
  /// the Restaurant Name). Submission requires it: the confirmation is what
  /// checks the mandatory photo + the name, and what looks for another
  /// unfinished submission for the same restaurant to combine with.
  bool _restaurantConfirmed = false;
  bool get restaurantConfirmed => _restaurantConfirmed;

  /// The "Confirm" action under the Restaurant Name. Needs the mandatory
  /// signboard/stall photo AND a non-blank name; returns the problem to show
  /// (the confirmation does not take), or null once confirmed.
  ///
  /// Confirming survives later edits to the OTHER fields (the tourist's
  /// choice), but two things take it back - both are what the click itself
  /// checked:
  ///   * a CHANGE of the restaurant name (the click validated the previous
  ///     name, and it is the moment another unfinished submission for the
  ///     same restaurant - same name + first food spot within 100 m - was
  ///     looked up; see [draftForRestaurantMerge] / [mergeExistingDraft]);
  ///   * a CHANGE of the signboard/stall photo ([setCapturedImage] - the
  ///     click is what checked that photo, and what enforced "one of the
  ///     two" - or [clearCapturedImage], which removes it).
  ///
  /// The click itself now also re-checks an EDITED name against the
  /// signboard photo ([hasEditedSignboardName]): Gemini's own reading needs
  /// no second opinion, but a name the tourist typed over it must still score
  /// [LandmarkSubmissionLogic.signboardNameMatchThreshold] on the same photo
  /// (see [nameMatchesSignboard]). A name that fails is NOT confirmed -
  /// [takeSignboardNameMismatch] reports it so the View can say so and offer
  /// [useSignboardName], and the field stays editable for another try.
  ///
  /// An unanswered check (offline, timeout, quota) fails OPEN: the form is
  /// confirmed as before, so a bad connection can never lock a tourist out.
  ///
  /// Returns the problem to show (the confirmation does not take), or null
  /// once confirmed.
  Future<String?> confirmRestaurant() async {
    if (!hasImageCaptured) {
      return 'Please capture a signboard or stall image.';
    }
    if (_restaurantName.trim().isEmpty) {
      return 'Enter the restaurant name before confirming.';
    }
    if (hasEditedSignboardName && _capturedImage != null) {
      _isConfirming = true;
      safeNotifyListeners();
      final bool matches = await _editedNameMatchesSignboard();
      _isConfirming = false;
      if (!matches) {
        _signboardNameMismatch = true;
        _restaurantConfirmed = false;
        safeNotifyListeners();
        return null;
      }
    }
    // LAST: is this restaurant already on the map under a name that only
    // LOOKS different ("Ali & Abu" vs "Ali and Abu")? The photos decide, and
    // the tourist has the final word - so the confirmation waits for that
    // answer (see [acceptSimilarPlace] / [rejectSimilarPlace]).
    final SimilarPlaceCandidate? similar = await _findSimilarPlace();
    if (similar != null) {
      _similarPlacePrompt = similar;
      _restaurantConfirmed = false;
      safeNotifyListeners();
      return null;
    }
    _restaurantConfirmed = true;
    safeNotifyListeners();
    return null;
  }

  /// The nearby place (within the same 100 m the merge uses) whose stored
  /// photo Gemini judges to be the SAME restaurant as this form's capture -
  /// nearest first, name-filtered before any photo is fetched. Null when
  /// there is no location, no capture, or nothing matches - and for every
  /// unanswerable check (offline, timeout, a photo that will not download):
  /// this can only ever ADD a question, never block a form the tourist can
  /// see is right.
  Future<SimilarPlaceCandidate?> _findSimilarPlace() async {
    final XFile? image = _capturedImage;
    final String name = _restaurantName.trim();
    if (image == null || name.isEmpty) return null;
    // Search only while the form is actually watched (the View subscribes
    // through the provider): headless and pure unit-test flows must never
    // fire network calls - the same rule the website probe follows.
    if (!hasListeners) return null;
    final TouristLocation location = _adjustedLocation.isKnown
        ? _adjustedLocation
        : baseLocation;
    if (!location.isKnown) return null;

    _isCheckingSimilarPlace = true;
    safeNotifyListeners();
    try {
      final List<SimilarPlaceCandidate> candidates = await landmarkLogic
          .similarNearbyPlaces(
            name: name,
            latitude: location.latitude,
            longitude: location.longitude,
          );
      if (candidates.isEmpty) return null;
      // The photo is read once - every candidate is compared with the SAME
      // capture.
      final List<int> bytes = await image.readAsBytes();
      for (final SimilarPlaceCandidate candidate in candidates) {
        final bool same = await landmarkLogic.photosShowSamePlace(
          imageBytes: bytes,
          candidate: candidate,
        );
        if (same) return candidate;
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      _isCheckingSimilarPlace = false;
      safeNotifyListeners();
    }
  }

  /// The tourist answered \"yes, that is the same place\". The form adopts
  /// that place's NAME - the whole submit path resolves the place by name
  /// (A13's same-name + 100 m lookup, the per-field hours/contact merge), so
  /// adopting it is what makes this submission join that place instead of
  /// creating a second record - then asks which of this form's dishes that
  /// place already lists (see [existingDishNames] / [allDishesExist]).
  Future<void> acceptSimilarPlace() async {
    final SimilarPlaceCandidate? candidate = _similarPlacePrompt;
    if (candidate == null) return;
    _similarPlacePrompt = null;
    if (candidate.name.trim().isNotEmpty &&
        candidate.name.trim() != _restaurantName) {
      // Also clears the confirmation (the name changed) - it is set again
      // below, now that the tourist has settled which place this is.
      setRestaurantName(candidate.name);
    }
    try {
      _existingDishNames = await landmarkLogic.dishesAlreadyAtPlace(
        candidate: candidate,
        dishes: formDishIdentities,
      );
    } catch (_) {
      _existingDishNames = const <String>[];
    }
    final List<({String name, String variant, int localFoodId})> dishes =
        formDishIdentities;
    _allDishesExist =
        dishes.isNotEmpty && _existingDishNames.length == dishes.length;
    _restaurantConfirmed = true;
    safeNotifyListeners();
  }

  /// The tourist answered \"no, it is a different place\": nothing is adopted
  /// and the form carries on as before - the confirmation is taken, so the
  /// click simply continues (the draft-combine offer included).
  void rejectSimilarPlace() {
    if (_similarPlacePrompt == null) return;
    _similarPlacePrompt = null;
    _restaurantConfirmed = true;
    safeNotifyListeners();
  }

  /// Drops the dishes the chosen place already lists from THIS form, after
  /// the acknowledgement - the additional foods go, and the names that were
  /// removed come back so the View can say so.
  ///
  /// A PRIMARY dish that already exists is deliberately NOT removed: it is
  /// what makes the form submittable, and the A13 merge skips it at write
  /// time anyway, so it never lands in the place twice either way.
  List<String> dropExistingDishes() {
    final List<String> existing = _existingDishNames;
    if (existing.isEmpty) return const <String>[];
    final List<String> removed = <String>[];
    for (final LandmarkFoodEntry entry in List<LandmarkFoodEntry>.of(
      _additionalFoods,
    )) {
      if (!existing.contains(entry.food.name)) continue;
      removed.add(entry.food.name);
      removeAdditionalFood(entry.entryId);
    }
    _existingDishNames = const <String>[];
    _allDishesExist = false;
    safeNotifyListeners();
    return removed;
  }

  /// The \"nothing to add\" ending: every dish on this form is already listed
  /// at the chosen place, so no submission is written. The incomplete
  /// submission is dropped with it (nothing is worth keeping - the dishes are
  /// on the map already) and the View leaves the form for the dashboard.
  Future<void> finishAsAlreadyThere() async {
    _existingDishNames = const <String>[];
    _allDishesExist = false;
    _restaurantConfirmed = false;
    safeNotifyListeners();
    await discardDraft();
  }

  /// The form's dishes in the shape the \"already listed there\" check takes:
  /// the name the tourist sees, the variant, and the catalogue id when the
  /// dish is curated (see `LandmarkSubmissionLogic.dishesAlreadyAtPlace`).
  List<({String name, String variant, int localFoodId})>
  get formDishIdentities => <({String name, String variant, int localFoodId})>[
    if (_primaryFood != null)
      (
        name: _primaryFood!.food.name,
        variant: _recognizedFoodVariant,
        localFoodId: _primaryFood!.food.id,
      ),
    for (final LandmarkFoodEntry entry in _additionalFoods)
      (
        name: entry.food.name,
        variant: entry.variant,
        localFoodId: entry.food.id,
      ),
  ];

  /// The plain message under the mismatch dialog (see
  /// [takeSignboardNameMismatch]). Deliberately non-technical: no score, no
  /// model talk - the tourist edited a name, and it is not the name on their
  /// photo.
  static const String signboardNameMismatchMessage =
      'The name you entered does not look like the name on your signboard '
      'photo. Please use the name shown on the signboard, or check your '
      'spelling.';

  /// Whether the last [confirmRestaurant] click was refused because the name
  /// no longer matches the signboard (see [signboardNameMismatchMessage]).
  /// One-shot, like the other take-style notices on this form.
  bool takeSignboardNameMismatch() {
    if (!_signboardNameMismatch) return false;
    _signboardNameMismatch = false;
    return true;
  }

  /// Puts Gemini's own signboard reading back into the name field - the
  /// "Use the signboard name" action on the mismatch dialog. The reading is
  /// restored through [setExtractedRestaurantName], so the field is
  /// force-synced even while focused and [hasEditedSignboardName] becomes
  /// false again (the name IS the reading, so the click needs no re-check).
  void useSignboardName() {
    final String? detected = _signboardDetectedName;
    if (detected == null) return;
    setExtractedRestaurantName(detected);
  }

  /// Asks Gemini whether the edited name still names the restaurant on the
  /// captured signboard. Unanswerable checks fail OPEN (true): the photo is
  /// re-looked-up only to REJECT a name, never to block the form on a network
  /// problem - the same fail-open choice [draftForRestaurantMerge] makes.
  Future<bool> _editedNameMatchesSignboard() async {
    final XFile? image = _capturedImage;
    if (image == null) return true;
    try {
      final List<int> bytes = await image.readAsBytes();
      return await landmarkLogic.nameMatchesSignboard(
        imageBytes: bytes,
        typedName: _restaurantName,
      );
    } catch (_) {
      return true;
    }
  }

  /// The saved incomplete submission for THIS restaurant - same name
  /// (trimmed, case/script-folded) and its first-food spot within 100 m of
  /// this form's (see
  /// `LandmarkLogicFacade.matchingLandmarkDraftForRestaurant`). A form
  /// continuing a draft never matches ITSELF - only another draft of the
  /// same restaurant (which is then absorbed: see [mergeExistingDraft]).
  /// Null when the name is blank, when the drafts cannot be read, or when
  /// nothing matches.
  Future<LandmarkDraft?> draftForRestaurantMerge() async {
    if (_restaurantName.trim().isEmpty) return null;
    try {
      final List<LandmarkDraft> drafts = await landmarkLogic
          .pendingLandmarkDrafts();
      return landmarkLogic.matchingLandmarkDraftForRestaurant(
        drafts: drafts,
        restaurantName: _restaurantName,
        formLocation: baseLocation,
        excludeDraftId: _draftId,
      );
    } catch (_) {
      // Best-effort - without the records this form simply stays its own.
      return null;
    }
  }

  /// Combines [draft] (another saved submission for this restaurant) INTO
  /// this form: the draft's dishes join as additional foods, its empty
  /// fields fill the ones this form left empty, and the two become ONE
  /// submission. A form that had never been saved adopts that draft's row
  /// (saving updates it); a form already CONTINUING its own draft keeps its
  /// row and remembers the absorbed draft, whose row is deleted once this
  /// form is saved (see [_deleteAbsorbedDrafts]). This form's own values
  /// always win: its price, photo, name and any field it already filled are
  /// never overwritten.
  ///
  /// Returns the labels of dishes this form already held and whose blank
  /// details were filled from the draft (shown as the merge notice); empty
  /// when nothing needed filling.
  List<String> mergeExistingDraft(LandmarkDraft draft) {
    final List<String> filled = <String>[];
    for (final LandmarkDraftFood saved in draft.foods) {
      if (_primaryFood != null &&
          landmarkLogic.isSameDishAndVariant(
            _primaryFood!.food,
            _primaryFood!.variant,
            saved.food,
            saved.variant,
          )) {
        // Already this form's first food - only fill its blanks.
        bool updated = false;
        if (_primaryFood!.price == null && saved.price != null) {
          _primaryFood = _primaryFood!.withPrice(saved.price!);
          updated = true;
        }
        if (_recognizedFoodImage == null &&
            _recognizedFoodImageRef == null &&
            saved.photo != null) {
          _recognizedFoodImageRef = saved.photo;
          updated = true;
        }
        if (updated) {
          filled.add(landmarkLogic.dishLabel(saved.food.name, saved.variant));
        }
        continue;
      }

      final int index = _additionalFoods.indexWhere(
        (LandmarkFoodEntry entry) => landmarkLogic.isSameDishAndVariant(
          entry.food,
          entry.variant,
          saved.food,
          saved.variant,
        ),
      );
      if (index == -1) {
        // A dish this form does not have yet - it joins as an added food.
        _additionalFoods = <LandmarkFoodEntry>[
          ..._additionalFoods,
          LandmarkFoodEntry.newEntry(
            food: saved.food,
            photoRef: saved.photo,
            price: saved.price,
            priceMin: saved.priceMin,
            priceMax: saved.priceMax,
            captureLocation: saved.captureLocation,
            variant: saved.variant,
            dietaryRestrictions: saved.dietaryRestrictions,
          ),
        ];
        continue;
      }

      LandmarkFoodEntry mine = _additionalFoods[index];
      bool updated = false;
      if (mine.price == null && saved.price != null) {
        mine = mine.withPrice(saved.price!);
        updated = true;
      }
      if (mine.photoRef == null && mine.image == null && saved.photo != null) {
        mine = mine.withPhotoRef(saved.photo!);
        updated = true;
      }
      if (updated) {
        _additionalFoods = List<LandmarkFoodEntry>.of(_additionalFoods);
        _additionalFoods[index] = mine;
        filled.add(landmarkLogic.dishLabel(saved.food.name, saved.variant));
      }
    }

    // Other fields: this form's value wins; the draft only fills blanks.
    if (_phone.trim().isEmpty && draft.phone.trim().isNotEmpty) {
      _phone = landmarkLogic.formatMalaysianPhone(draft.phone);
    }
    if (_website.trim().isEmpty && draft.website.trim().isNotEmpty) {
      _website = draft.website;
    }
    if (_address.trim().isEmpty && draft.address.trim().isNotEmpty) {
      _address = draft.address;
      // A draft does not record where its address came from; treating it as
      // hand-entered keeps it safe (map moves leave it alone).
      _addressFromMap = false;
    }
    if (!_adjustedLocation.isKnown && draft.adjustedLocation.isKnown) {
      _adjustedLocation = draft.adjustedLocation;
    }
    // Opening hours merge DAY BY DAY: a day this form carries nothing for
    // takes the draft's hours, a day this form filled keeps its own. The
    // form's default "unknown" placeholder row counts as nothing - it is
    // just the empty editor state, not an entered value.
    bool dayHasValue(List<OpeningHour> rows) =>
        rows.any((OpeningHour hour) => hour.status != DayStatus.unknown);
    final Map<Weekday, List<OpeningHour>> mergedHours =
        Map<Weekday, List<OpeningHour>>.of(_operatingHours);
    draft.operatingHours.forEach((Weekday day, List<OpeningHour> hours) {
      final List<OpeningHour> mine = mergedHours[day] ?? const <OpeningHour>[];
      if (!dayHasValue(mine) && dayHasValue(hours)) mergedHours[day] = hours;
    });
    _operatingHours = mergedHours;

    // A form that was never saved adopts that submission's row - saving then
    // updates it. A form CONTINUING its own draft keeps its row and notes
    // the other draft as absorbed: its row is removed once this form is
    // saved, so the restaurant still keeps ONE submission.
    if (_draftId == 0) {
      _draftId = draft.id;
    } else if (draft.id != _draftId) {
      _absorbedDraftIds.add(draft.id);
    }
    safeNotifyListeners();
    return filled;
  }

  /// Removes the rows of drafts that were COMBINED into this form (see
  /// [mergeExistingDraft]). Best-effort, and called only AFTER this form's
  /// own row has been written, so an abandoned form can never lose the other
  /// submission's data. The rows' photos are kept - the combined form
  /// references them.
  Future<void> _deleteAbsorbedDrafts() async {
    if (_absorbedDraftIds.isEmpty) return;
    final List<int> ids = List<int>.of(_absorbedDraftIds);
    _absorbedDraftIds.clear();
    for (final int id in ids) {
      try {
        await landmarkLogic.clearSubmittedLandmarkDraft(id);
      } catch (_) {
        // Best-effort - an orphaned row expires on its own.
      }
    }
  }

  /// Optional contact/address setters - capped to their field limits while
  /// typing (the View's TextField maxLength enforces the same cap).
  ///
  /// The phone field is digits-only and shows a fixed "+60" beside it (see
  /// `_ContactDetailsSection`), but the STORED value matches the `restaurant`
  /// table's own style: national digits with the trunk "0", grouped by
  /// number type - "0126840922" and "126840922" both store "012-684 0922".
  /// An incomplete entry (or one with nothing to dial) stays as its digits,
  /// so nothing is mangled while the tourist is still typing.
  void setRestaurantPhone(String value) {
    _phone = _clampTo(
      landmarkLogic.formatMalaysianPhone(value),
      landmarkLogic.maxPhoneLength,
    );
    safeNotifyListeners();
  }

  void setRestaurantWebsite(String value) {
    _website = _clampTo(value, landmarkLogic.maxWebsiteLength);
    _scheduleWebsiteLinkCheck();
    safeNotifyListeners();
  }

  /// Debounced live probe of the website field: after typing pauses and the
  /// value is a well-formed link, the app tries to open it - a dead or
  /// mistyped address surfaces while the tourist is still on the form, not
  /// only at submit. A failed probe DISABLES Submit (see [canSubmit] and
  /// [websiteLinkStatus]); [submitLandmark] still re-probes and blocks on its
  /// own result, which stays the authority.
  void _scheduleWebsiteLinkCheck() {
    _websiteLinkDebounce?.cancel();
    _websiteLinkChecking = false;
    _websiteLinkUnreachable = false;
    final String url = _website.trim();
    if (url.isEmpty || url.length > landmarkLogic.maxWebsiteLength) return;
    if (!landmarkLogic.isValidWebsiteFormat(url)) return;
    // Probe only while the form is actually watched (the View subscribes
    // through the provider): headless and pure unit-test flows must never
    // fire network calls.
    if (!hasListeners) return;
    _websiteLinkDebounce = Timer(websiteLinkCheckDelay, () {
      unawaited(_probeWebsiteLink(url));
    });
  }

  Future<void> _probeWebsiteLink(String url) async {
    _websiteLinkChecking = true;
    safeNotifyListeners();
    bool reachable;
    try {
      reachable =
          await (_websiteReachability?.call(url) ??
              landmarkLogic.isWebsiteReachable(url));
    } catch (_) {
      // A broken probe must never claim the link is bad - the submit-time
      // check stays the authority.
      reachable = true;
    }
    if (_website.trim() != url) return; // The field changed while probing.
    _websiteLinkChecking = false;
    _websiteLinkUnreachable = !reachable;
    safeNotifyListeners();
  }

  void setRestaurantAddress(String value) {
    final String next = _clampTo(value, landmarkLogic.maxAddressLength);
    final bool changed = next != _address;
    _address = next;
    if (changed) {
      // The tourist's own words from here on: map moves leave them alone,
      // and a previous "too far from the pin" warning no longer applies.
      _addressFromMap = false;
      _addressPinWarning = null;
      _scheduleAddressSearch();
    }
    safeNotifyListeners();
  }

  /// Caps [value] at [maxLength] characters so a pasted blob can never
  /// exceed a field's limit (belt-and-suspenders behind TextField maxLength).
  static String _clampTo(String value, int maxLength) =>
      value.length <= maxLength ? value : value.substring(0, maxLength);

  // ===========================================================================
  // Address ↔ map binding (OpenStreetMap / Nominatim)
  // ===========================================================================

  /// Typing must pause this long before the address search fires (Nominatim
  /// allows ~1 request/second; the repository throttles as well).
  static const Duration addressSearchDebounce = Duration(milliseconds: 600);

  /// How long a pin move waits before its address lookup fires - a dropped
  /// pin must not storm the geocoder while it settles.
  static const Duration mapAddressLookupDelay = Duration(milliseconds: 500);

  /// Whether the "Use the map pin's address" button has something to offer:
  /// the pin produced an address, it differs from the field, and the field
  /// holds the tourist's own text.
  bool get canApplyMapAddress =>
      !_addressFromMap &&
      _mapDerivedAddress != null &&
      _mapDerivedAddress!.isNotEmpty &&
      _mapDerivedAddress != _address;

  /// The address section's status line: the pin lookup running, or the
  /// inline notice when the spot has no address to give. Null while idle or
  /// after a successful lookup.
  String? get mapAddressStatus {
    if (_mapAddressLookupRunning) return 'Looking up the address…';
    if (_mapAddressUnavailable) {
      return "We couldn't find an address for this spot. Drag the pin "
          'again, or type the address yourself.';
    }
    return null;
  }

  /// The address search's status line: running, unavailable, or nothing
  /// found. Null while idle or when suggestions are shown.
  String? get addressSearchStatus {
    if (_addressSearchRunning) return 'Searching for addresses…';
    if (_addressSearchUnavailable) {
      return 'Address search is unavailable right now. You can still type '
          'the address yourself.';
    }
    if (_addressSearchEmpty) {
      return 'No matching addresses found. You can still type the address '
          'yourself.';
    }
    return null;
  }

  /// How a suggestion's distance is labelled ("350 m", "1.2 km") - flat
  /// passthrough to the logic rule, so the View never formats numbers itself.
  String formatDistance(double metres) => landmarkLogic.formatDistance(metres);

  /// Fills an EMPTY address from the pinned spot when the form opens (the
  /// View calls this after its first frame). Never overwrites a resumed
  /// draft's address, nor anything typed.
  void prefillAddressFromMap() {
    if (_address.trim().isNotEmpty) return;
    _scheduleMapAddressLookup();
  }

  /// Picks a suggestion from the dropdown: its text lands in the address
  /// field, and when the place is within the pin's 100 m range the pin MOVES
  /// there too. A farther place fills the text only - with an amber warning
  /// that says so (submission stays allowed; only the pin stays put).
  void selectAddressSuggestion(AddressSuggestion suggestion) {
    final String text = _clampTo(
      suggestion.address,
      landmarkLogic.maxAddressLength,
    );
    _clearAddressSearch();
    _addressPinWarning = null;

    final TouristLocation spot = TouristLocation(
      latitude: suggestion.latitude,
      longitude: suggestion.longitude,
    );
    final double distance = baseLocation.isKnown
        ? landmarkLogic.distanceMetres(baseLocation, spot)
        : 0;

    if (!landmarkLogic.isWithinAllowedRange(
      baseLocation,
      spot.latitude,
      spot.longitude,
    )) {
      // Too far for the pin (A9.1) - keep the chosen text, warn, move nothing.
      _address = text;
      _addressFromMap = false;
      _addressVersion++;
      _addressPinWarning =
          'This address is ${landmarkLogic.formatDistance(distance)} from '
          'your captured location - beyond the '
          '${landmarkLogic.pinAdjustmentRangeMetres.round()} m pin range, so '
          'the pin stays where it is. The address is still saved.';
      safeNotifyListeners();
      return;
    }

    _address = text;
    _addressFromMap = true;
    _addressVersion++;
    _keepSelectedAddressFor = spot;
    // Reuses the pin-move path for its range AND land validation.
    adjustLandmarkLocation(spot.latitude, spot.longitude);
    if (_locationError != null) {
      // The pin refused the move (e.g. the spot is off land): keep the
      // selected text, but it no longer describes the pin.
      _keepSelectedAddressFor = null;
      _addressFromMap = false;
      _addressPinWarning = _locationError;
    }
    safeNotifyListeners();
  }

  /// Applies the pinned spot's composed address to the field (the "Use the
  /// map pin's address" button) - the tourist chose the map's wording over
  /// their typed text.
  void applyMapAddressFromPin() {
    final String? address = _mapDerivedAddress;
    if (address == null || address.isEmpty) return;
    _address = _clampTo(address, landmarkLogic.maxAddressLength);
    _addressFromMap = true;
    _addressPinWarning = null;
    _addressVersion++;
    _clearAddressSearch();
    safeNotifyListeners();
  }

  /// Drops every suggestion-search state - used when a pick or the map's own
  /// address settles the field.
  void _clearAddressSearch() {
    _addressSearchDebounce?.cancel();
    _addressSearchToken++;
    _addressSuggestions = const <AddressSuggestion>[];
    _addressSearchRunning = false;
    _addressSearchUnavailable = false;
    _addressSearchEmpty = false;
  }

  /// Schedules the pin's reverse lookup (debounced). No listeners means no
  /// form is watching (pure unit tests must never call the network), and no
  /// location means there is nothing to look up.
  void _scheduleMapAddressLookup() {
    _mapAddressDebounce?.cancel();
    final TouristLocation target = _adjustedLocation.isKnown
        ? _adjustedLocation
        : baseLocation;
    if (!target.isKnown || !hasListeners) return;
    _mapAddressDebounce = Timer(
      mapAddressLookupDelay,
      () => unawaited(_lookupMapAddress(target)),
    );
  }

  Future<void> _lookupMapAddress(TouristLocation target) async {
    _mapAddressLookupRunning = true;
    _mapAddressUnavailable = false;
    safeNotifyListeners();

    String? address;
    try {
      address = await landmarkLogic.reverseGeocodeAddress(target);
    } catch (_) {
      address = null;
    }

    // The pin may have moved again while this ran - drop a stale answer.
    final TouristLocation current = _adjustedLocation.isKnown
        ? _adjustedLocation
        : baseLocation;
    if (!_sameSpot(current, target)) return;

    _mapAddressLookupRunning = false;
    if (address == null || address.isEmpty) {
      _mapAddressUnavailable = true;
      _keepSelectedAddressFor = null;
      safeNotifyListeners();
      return;
    }

    _mapAddressUnavailable = false;
    _mapDerivedAddress = _clampTo(address, landmarkLogic.maxAddressLength);
    final bool keepSelected =
        _keepSelectedAddressFor != null &&
        _sameSpot(target, _keepSelectedAddressFor!);
    if (keepSelected) {
      // He picked those words - the lookup only refreshes the map's copy.
      _keepSelectedAddressFor = null;
    } else if (_addressFromMap || _address.trim().isEmpty) {
      // The field follows the pin from now on (until the tourist types).
      _address = _mapDerivedAddress!;
      _addressFromMap = true;
      _addressPinWarning = null;
      _addressVersion++;
    }
    safeNotifyListeners();
  }

  /// Schedules the suggestion search for the text just typed (debounced,
  /// >= [LandmarkSubmissionLogic.minAddressSearchLength] characters).
  /// Typing alone never moves the pin - only picking a suggestion does.
  void _scheduleAddressSearch() {
    _addressSearchDebounce?.cancel();
    _addressSearchToken++;
    final String query = _address.trim();
    if (query.length < landmarkLogic.minAddressSearchLength) {
      _addressSuggestions = const <AddressSuggestion>[];
      _addressSearchRunning = false;
      _addressSearchUnavailable = false;
      _addressSearchEmpty = false;
      return;
    }
    if (!hasListeners) return;
    final int token = _addressSearchToken;
    _addressSearchDebounce = Timer(
      addressSearchDebounce,
      () => unawaited(_searchAddresses(query, token)),
    );
  }

  Future<void> _searchAddresses(String query, int token) async {
    if (_address.trim() != query) return;
    final TouristLocation around = baseLocation.isKnown
        ? baseLocation
        : _currentLocation;
    _addressSearchRunning = true;
    _addressSearchUnavailable = false;
    _addressSearchEmpty = false;
    safeNotifyListeners();

    List<AddressSuggestion>? results;
    try {
      results = await landmarkLogic.searchAddresses(
        query: query,
        around: around,
      );
    } catch (_) {
      results = null;
    }

    // A stale response (newer query, or the text changed meanwhile) is
    // dropped silently.
    if (token != _addressSearchToken || _address.trim() != query) return;

    _addressSearchRunning = false;
    if (results == null) {
      _addressSuggestions = const <AddressSuggestion>[];
      _addressSearchUnavailable = true;
    } else {
      _addressSuggestions = results;
      _addressSearchEmpty = results.isEmpty;
    }
    safeNotifyListeners();
  }

  static bool _sameSpot(TouristLocation a, TouristLocation b) =>
      a.latitude == b.latitude && a.longitude == b.longitude;

  /// Set a day's status (Open / Unknown / Closed - BF-19..23, A14, A15).
  /// Not a plain open/closed toggle: "Unknown" is a real third answer, not
  /// a UI decoration - see `OpeningHour.status`'s doc.
  ///
  /// Closed/Unknown always collapse to a single row with no times - there's
  /// nothing for them to carry, matching the real table (their rows have
  /// null `opening_time`/`closing_time`). Switching to Open keeps any
  /// existing Open rows if there are already some; otherwise seeds one
  /// fresh, empty row so there's something to edit.
  void setDayStatus(Weekday day, DayStatus status) {
    final List<OpeningHour> existing =
        _operatingHours[day] ?? const <OpeningHour>[];
    final List<OpeningHour> updated;
    if (status == DayStatus.open) {
      final List<OpeningHour> openRows = existing
          .where((OpeningHour hour) => hour.status == DayStatus.open)
          .toList();
      updated = openRows.isNotEmpty
          ? openRows
          : <OpeningHour>[OpeningHour(id: 0, day: day, status: DayStatus.open)];
    } else {
      final int id = existing.isNotEmpty ? existing.first.id : 0;
      updated = <OpeningHour>[OpeningHour(id: id, day: day, status: status)];
    }
    _operatingHours = Map<Weekday, List<OpeningHour>>.of(_operatingHours)
      ..[day] = updated;
    safeNotifyListeners();
  }

  /// Adds a new, empty row to [day] - the "+" button at the end of its
  /// operating-hours row. A day can have more than one row when Open (e.g.
  /// a midday closure: "12:00-14:00" then "15:00-20:00").
  void addTimeRange(Weekday day) {
    final List<OpeningHour> existing =
        _operatingHours[day] ?? const <OpeningHour>[];
    _operatingHours = Map<Weekday, List<OpeningHour>>.of(_operatingHours)
      ..[day] = <OpeningHour>[
        ...existing,
        OpeningHour(id: 0, day: day, status: DayStatus.open),
      ];
    safeNotifyListeners();
  }

  /// Removes one row from [day], by its index. The View only shows a remove
  /// control when a day has more than one row, so this should never
  /// actually be asked to remove the last one - guarded here anyway rather
  /// than trusting that.
  void removeTimeRange(Weekday day, int rangeIndex) {
    final List<OpeningHour>? existing = _operatingHours[day];
    if (existing == null || existing.length <= 1) return;
    if (rangeIndex < 0 || rangeIndex >= existing.length) return;
    final List<OpeningHour> updated = List<OpeningHour>.of(existing)
      ..removeAt(rangeIndex);
    _operatingHours = Map<Weekday, List<OpeningHour>>.of(_operatingHours)
      ..[day] = updated;
    safeNotifyListeners();
  }

  /// Sets one row's opening or closing time, by its index within [day].
  void setRangeTime(
    Weekday day,
    int rangeIndex,
    bool isOpeningTime,
    int minutes,
  ) {
    final List<OpeningHour>? existing = _operatingHours[day];
    if (existing == null || rangeIndex < 0 || rangeIndex >= existing.length) {
      return;
    }
    final OpeningHour row = existing[rangeIndex];
    final int? opening = isOpeningTime ? minutes : row.opensAt;
    int? closing = isOpeningTime ? row.closesAt : minutes;

    // A closing time at or BEFORE the opening time means the NEXT day
    // ("10:00 -> 02:00"): encoded as minutes past midnight + 1440, which is
    // also how it is persisted - split into Monday 10:00-24:00 + Tuesday
    // 00:00-02:00, see `OpeningHoursRows`. Changing the opening time
    // re-encodes an existing close against it, so a night period that has
    // been re-timed into the morning stops being overnight.
    if (opening != null && closing != null) {
      closing = landmarkLogic.encodeCloseTime(
        opensAt: opening,
        closeMinutes: closing,
      );
    }

    final List<OpeningHour> updated = List<OpeningHour>.of(existing);
    updated[rangeIndex] = OpeningHour(
      id: row.id,
      day: day,
      status: row.status,
      opensAt: opening,
      closesAt: closing,
    );
    _operatingHours = Map<Weekday, List<OpeningHour>>.of(_operatingHours)
      ..[day] = updated;
    safeNotifyListeners();
  }

  /// "Copy Monday to All Weekdays" - applies Monday's status AND every row
  /// to Tuesday through Friday (weekdays only - Saturday/Sunday are left
  /// alone, since they're commonly different, e.g. the "Unknown"/"Closed"
  /// case in the mock-up). Does nothing if Monday itself is still closed
  /// (nothing worth copying).
  void copyMondayToAllWeekdays() {
    final List<OpeningHour>? monday = _operatingHours[Weekday.monday];
    if (monday == null ||
        monday.isEmpty ||
        monday.first.status == DayStatus.closed) {
      return;
    }

    const List<Weekday> weekdays = <Weekday>[
      Weekday.tuesday,
      Weekday.wednesday,
      Weekday.thursday,
      Weekday.friday,
    ];

    final Map<Weekday, List<OpeningHour>> updated =
        Map<Weekday, List<OpeningHour>>.of(_operatingHours);
    for (final Weekday day in weekdays) {
      updated[day] = <OpeningHour>[
        for (final OpeningHour hour in monday)
          OpeningHour(
            id: 0,
            day: day,
            status: hour.status,
            opensAt: hour.opensAt,
            closesAt: hour.closesAt,
          ),
      ];
    }
    _operatingHours = updated;
    safeNotifyListeners();
  }

  /// Add additional food via camera (A12). Opens `FoodRecognitionView` in
  /// additional-food-capture mode and waits for the recognized food (and
  /// its photo) to come back - same pop-with-result pattern as
  /// [openSignboardCapture]. Price starts unset - the tourist enters it on
  /// this food's card, same as the primary food. The first food's capture
  /// spot is handed over as the reference location so the camera can block a
  /// capture taken more than 50 m away; the check is repeated here.
  Future<void> openAddMoreFood() async {
    _clearCaptureRejection();
    LandmarkDraftHandoff().pendingPurpose =
        FoodRecognitionPurpose.additionalFood;
    LandmarkDraftHandoff().pendingReferenceLocation = baseLocation.isKnown
        ? baseLocation
        : null;
    // The dishes this form already holds ride along, so the camera screen
    // can withhold its "Add to Landmark" for a re-captured duplicate and say
    // why THERE - instead of the tourist landing back here with a notice.
    LandmarkDraftHandoff().pendingExistingFormFoods = formFoodIdentities;
    final AdditionalFoodCaptureResult? result =
        await AppNavigator.push<AdditionalFoodCaptureResult>(
          AppRoutes.foodRecognition,
        );
    if (result == null) return; // Tourist backed out without confirming.
    if (!_acceptCaptureLocation(result.captureLocation, 'This food')) return;
    addAdditionalFood(
      result.food,
      image: result.image,
      priceMin: result.priceMin,
      priceMax: result.priceMax,
      captureLocation: result.captureLocation,
      variant: result.variant,
      dietaryRestrictions: result.dietaryRestrictions,
    );
  }

  /// The dishes already on this form - the "same thing to add?" identities
  /// (dish + variant, synonyms included) the additional-food camera screen
  /// checks a fresh capture against, so a duplicate is blocked THERE (see
  /// [openAddMoreFood]).
  List<ExistingFormFood> get formFoodIdentities => <ExistingFormFood>[
    if (_primaryFood != null)
      (food: _primaryFood!.food, variant: _primaryFood!.variant),
    for (final LandmarkFoodEntry entry in _additionalFoods)
      (food: entry.food, variant: entry.variant),
  ];

  /// The notice for a duplicate dish - shared with the capture screen's
  /// blocking message so the two wordings can never drift apart.
  String get duplicateFoodNotice => landmarkLogic.duplicateFoodNotice;

  /// Add additional food directly (used when the food is already in hand -
  /// prefer [openAddMoreFood] from the View).
  ///
  /// A dish that is ALREADY on this form with the SAME variant is rejected
  /// ([takeDuplicateFoodNotice] reports it so the View can say why) - one
  /// form cannot hold the same food twice. A different variant is a
  /// different thing to add and is accepted - but a spelling that only
  /// repeats the dish or one of its curated synonyms ("Ais Kacang (ABC)") is
  /// NOT a different variant (see
  /// `LandmarkSubmissionLogic.sameDishAndVariantIdentity`).
  void addAdditionalFood(
    LocalFood food, {
    XFile? image,
    double priceMin = 0,
    double priceMax = 0,
    TouristLocation captureLocation = TouristLocation.unknown,
    String variant = '',
    List<String> dietaryRestrictions = const <String>[],
  }) {
    if (_isAlreadyOnForm(food, variant)) {
      _duplicateFoodRejected = true;
      safeNotifyListeners();
      return;
    }
    _additionalFoods = <LandmarkFoodEntry>[
      ..._additionalFoods,
      LandmarkFoodEntry.newEntry(
        food: food,
        image: image,
        priceMin: priceMin,
        priceMax: priceMax,
        captureLocation: captureLocation,
        variant: variant,
        dietaryRestrictions: dietaryRestrictions,
      ),
    ];
    safeNotifyListeners();
  }

  /// Whether [food] + [variant] is already on this form - the primary food or
  /// any additional food holding the SAME dish and variant (see
  /// `LandmarkSubmissionLogic.isSameDishAndVariant`). A different variant is
  /// not a duplicate - unless it only repeats the dish or one of its curated
  /// synonyms, which is the same dish spelled out.
  bool _isAlreadyOnForm(LocalFood food, String variant) {
    final LandmarkFoodEntry? primary = _primaryFood;
    if (primary != null &&
        landmarkLogic.isSameDishAndVariant(
          primary.food,
          primary.variant,
          food,
          variant,
        )) {
      return true;
    }
    for (final LandmarkFoodEntry entry in _additionalFoods) {
      if (landmarkLogic.isSameDishAndVariant(
        entry.food,
        entry.variant,
        food,
        variant,
      )) {
        return true;
      }
    }
    return false;
  }

  /// Set the price for one additional food, by its form-local [entryId] -
  /// NOT `LocalFood.id`, which is `0` for every unsaved food. (A16)
  void setAdditionalFoodPrice(int entryId, double price) {
    if (!landmarkLogic.isValidPrice(price)) {
      _submitError =
          'Price must be between ${landmarkLogic.minPrice} and '
          '${landmarkLogic.maxPrice} MYR';
      safeNotifyListeners();
      return;
    }
    LandmarkFoodEntry? entry;
    for (final LandmarkFoodEntry e in _additionalFoods) {
      if (e.entryId == entryId) {
        entry = e;
        break;
      }
    }
    if (entry == null) return;
    _additionalFoods = _additionalFoods
        .map(
          (LandmarkFoodEntry e) =>
              e.entryId == entryId ? e.withPrice(price) : e,
        )
        .toList(growable: false);
    final String? warning = landmarkLogic.suggestedPriceWarning(
      entry.food.name,
      price,
      entry.priceMin,
      entry.priceMax,
    );
    if (warning == null) {
      _additionalFoodPriceWarnings.remove(entryId);
    } else {
      _additionalFoodPriceWarnings[entryId] = warning;
    }
    _submitError = null;
    safeNotifyListeners();
  }

  /// Remove additional food, by its form-local [entryId].
  void removeAdditionalFood(int entryId) {
    _additionalFoods = _additionalFoods
        .where((LandmarkFoodEntry entry) => entry.entryId != entryId)
        .toList(growable: false);
    _additionalFoodPriceWarnings.remove(entryId);
    safeNotifyListeners();
  }

  /// Day names for validation messages - `_dayLabels` in the View uses
  /// 3-letter abbreviations for the compact grid, but an error message
  /// reads better with the day spelled out.
  static const Map<Weekday, String> _dayNames = <Weekday, String>{
    Weekday.monday: 'Monday',
    Weekday.tuesday: 'Tuesday',
    Weekday.wednesday: 'Wednesday',
    Weekday.thursday: 'Thursday',
    Weekday.friday: 'Friday',
    Weekday.saturday: 'Saturday',
    Weekday.sunday: 'Sunday',
  };

  /// Checks every day's operating-hours rows for the ONE thing that's a
  /// UI/form concern, not a domain rule: every Open row needs both an
  /// opening and closing time set (BF-19..23). A range being half-filled
  /// only means anything because a human is mid-way through typing into
  /// this specific form - it's not a rule the data itself must obey once
  /// saved, so it stays here rather than in `LandmarkSubmissionLogic`.
  ///
  /// The other two rules (closing after opening, no overlap) ARE domain
  /// invariants - true of an `OpeningHour` no matter where it came from -
  /// so they live in `LandmarkSubmissionLogic.validateOperatingHours`
  /// instead, called via the facade below rather than duplicated here.
  ///
  /// Returns a user-facing message describing the first problem found, or
  /// null once everything is valid. Not run immediately on every dropdown
  /// change (unlike price validation) - while a tourist is mid-way through
  /// filling in a new range, flagging it as "incomplete" before they've
  /// reached the second dropdown would be premature. Instead this gates
  /// [canSubmit] and is re-checked with this message at actual submit time.
  String? _operatingHoursError() {
    for (final MapEntry<Weekday, List<OpeningHour>> entry
        in _operatingHours.entries) {
      final String dayName = _dayNames[entry.key]!;
      final bool hasIncompleteOpenRow = entry.value.any(
        (OpeningHour hour) =>
            hour.status == DayStatus.open &&
            (hour.opensAt == null || hour.closesAt == null),
      );
      if (hasIncompleteOpenRow) {
        return 'Please set both an opening and closing time for $dayName.';
      }
    }
    return landmarkLogic.validateOperatingHours(_operatingHours);
  }

  // --- DRAFT (INCOMPLETE SUBMISSION) COMMANDS ---

  /// Whether the form holds anything worth keeping as an incomplete
  /// submission - a recognized food, a captured photo, or a typed name.
  bool get hasDraftContent =>
      _primaryFood != null ||
      _capturedImage != null ||
      _capturedImageRef != null ||
      _restaurantName.trim().isNotEmpty ||
      _additionalFoods.isNotEmpty;

  /// Restores a saved draft onto this form - everything the tourist had
  /// entered: names/contact details, the landmark photo, every food with its
  /// price and photo, the opening hours, and the location (the first food's
  /// captured spot, plus a hand-moved pin if there was one). Called from
  /// `AddLandmarkView.initState` when the form was opened to continue a
  /// draft.
  void restoreDraft(LandmarkDraft draft) {
    _draftId = draft.id;
    _restaurantConfirmed = draft.restaurantConfirmed;
    _restaurantName = draft.restaurantName;
    // Stored the way the restaurant table stores phones (see
    // [setRestaurantPhone]) - a legacy draft's shape is normalised here too.
    _phone = landmarkLogic.formatMalaysianPhone(draft.phone);
    _website = draft.website;
    _address = draft.address;
    // See [mergeExistingDraft]: a restored address is treated as the
    // tourist's own text, never as map-sourced.
    _addressFromMap = false;
    // A stored draft is not probed until something changes or submit runs.
    _websiteLinkDebounce?.cancel();
    _websiteLinkChecking = false;
    _websiteLinkUnreachable = false;
    _captureLocation = draft.baseLocation;
    _adjustedLocation = draft.adjustedLocation;

    final LandmarkDraftPhoto? landmarkPhoto = draft.landmarkPhoto;
    if (landmarkPhoto != null) {
      _capturedImageRef = landmarkPhoto;
      _capturedImageType = landmarkPhoto.type;
      _capturedImageLocation = landmarkPhoto.captureLocation;
      _isSignboardDisabled = _capturedImageType == 'stall';
      _isStallDisabled = _capturedImageType == 'signboard';
    }

    if (draft.foods.isNotEmpty) {
      final LandmarkDraftFood primary = draft.foods.first;
      _recognizedFoodConfidence = primary.confidence;
      _recognizedFoodDietaryRestrictions = primary.dietaryRestrictions;
      _recognizedFoodVariant = primary.variant;
      _recognizedFoodImageRef = primary.photo;
      _primaryFood = LandmarkFoodEntry.newEntry(
        food: primary.food,
        price: primary.price,
        priceMin: primary.priceMin,
        priceMax: primary.priceMax,
        captureLocation: primary.captureLocation.isKnown
            ? primary.captureLocation
            : draft.baseLocation,
        variant: primary.variant,
      );
      for (final LandmarkDraftFood food in draft.foods.skip(1)) {
        _additionalFoods = <LandmarkFoodEntry>[
          ..._additionalFoods,
          LandmarkFoodEntry.newEntry(
            food: food.food,
            photoRef: food.photo,
            price: food.price,
            priceMin: food.priceMin,
            priceMax: food.priceMax,
            captureLocation: food.captureLocation,
            variant: food.variant,
            dietaryRestrictions: food.dietaryRestrictions,
          ),
        ];
      }
    }
    if (draft.operatingHours.isNotEmpty) {
      _operatingHours = draft.operatingHours;
    }
    safeNotifyListeners();
  }

  /// Snapshots the form as a [LandmarkDraft]. Null when there is nothing
  /// worth keeping. `expiresAt`/`updatedAt` are placeholders here - the
  /// logic layer stamps the real 24-hour expiry on save.
  LandmarkDraft? _buildDraft() {
    if (!hasDraftContent) return null;
    final DateTime now = DateTime.now();
    return LandmarkDraft(
      id: _draftId,
      restaurantName: _restaurantName,
      phone: _phone,
      website: _website,
      address: _address,
      category: _primaryFood?.food.category ?? '',
      restaurantConfirmed: _restaurantConfirmed,
      baseLocation: baseLocation,
      adjustedLocation: _adjustedLocation,
      landmarkPhoto: _capturedImageRef,
      foods: <LandmarkDraftFood>[
        if (_primaryFood != null)
          LandmarkDraftFood(
            food: _primaryFood!.food,
            price: _primaryFood!.price,
            priceMin: _primaryFood!.priceMin,
            priceMax: _primaryFood!.priceMax,
            confidence: _recognizedFoodConfidence,
            dietaryRestrictions: _recognizedFoodDietaryRestrictions,
            variant: _recognizedFoodVariant,
            captureLocation: _captureLocation,
            photo: _recognizedFoodImageRef,
          ),
        for (final LandmarkFoodEntry entry in _additionalFoods)
          LandmarkDraftFood(
            food: entry.food,
            price: entry.price,
            priceMin: entry.priceMin,
            priceMax: entry.priceMax,
            dietaryRestrictions: entry.dietaryRestrictions,
            variant: entry.variant,
            captureLocation: entry.captureLocation,
            photo: entry.photoRef,
          ),
      ],
      operatingHours: _operatingHours,
      expiresAt: now,
      updatedAt: now,
    );
  }

  /// Saves the form as an incomplete submission (draft) - uploads any photos
  /// that were only captured on this device, then writes/updates the draft
  /// row. Kept for 24 hours from this save; the tourist can continue it from
  /// the camera's "continue" prompt or the profile's incomplete-submission
  /// list. A second save updates the SAME row.
  ///
  /// [background] marks a save triggered by the app going to the background -
  /// the tourist is not looking, so a failure stays quiet and a success is
  /// NOT announced at all: the form is still on screen, untouched, and the
  /// saved row is visible in Profile -> Incomplete Submissions (user request
  /// 2026-09-13: no "saved" snackbar).
  /// Returns whether anything was written.
  Future<bool> saveDraft({bool background = false}) async {
    if (_draftSaving) return false;
    if (!hasDraftContent) return false;
    _draftSaving = true;
    try {
      await _uploadOutstandingPhotos();
      final LandmarkDraft? draft = _buildDraft();
      if (draft == null) return false;
      final int id = await landmarkLogic.saveLandmarkDraft(draft);
      if (id == 0) return false; // Not signed in - nothing was written.
      _draftId = id;
      // The combined-away drafts' rows go with this save - their dishes are
      // now on THIS form (see [mergeExistingDraft]).
      await _deleteAbsorbedDrafts();
      return true;
    } catch (_) {
      // Saving a draft must never block leaving the form - report the
      // failure only while the tourist is still looking at it. Never the
      // raw error: the same friendly line the View shows for this failure.
      if (!background) {
        _submitError =
            'Could not save the incomplete submission. '
            'Check your connection and try again.';
      }
      return false;
    } finally {
      _draftSaving = false;
      safeNotifyListeners();
    }
  }

  /// Discards the form AND any saved draft row for it, including the photos
  /// already uploaded for it. Used when the tourist chooses not to keep an
  /// incomplete submission.
  Future<void> discardDraft() async {
    final LandmarkDraft? draft = _buildDraft();
    if (draft == null) return;
    try {
      await landmarkLogic.discardLandmarkDraft(draft);
    } catch (_) {
      // Best-effort - the tourist leaves the form regardless.
    }
    _draftId = 0;
    // Discarding THIS form must not delete a draft it had combined with -
    // that submission stays exactly where it was.
    _absorbedDraftIds.clear();
    safeNotifyListeners();
  }

  /// Removes the draft row after a SUCCESSFUL submission. Its photos are
  /// NOT deleted - the submitted landmark now stores those same objects.
  Future<void> clearSubmittedDraft() async {
    if (_draftId == 0) return;
    try {
      await landmarkLogic.clearSubmittedLandmarkDraft(_draftId);
    } catch (_) {
      // Best-effort - an orphaned draft row is harmless (it expires).
    }
    _draftId = 0;
    // Any combined-away drafts are part of this submission now.
    await _deleteAbsorbedDrafts();
  }

  /// Uploads every photo that exists only on this device (a local capture
  /// with no stored reference yet), so the draft can be resumed with those
  /// photos on any device. Already-uploaded photos are skipped.
  Future<void> _uploadOutstandingPhotos() async {
    final XFile? landmarkImage = _capturedImage;
    if (landmarkImage != null && _capturedImageRef == null) {
      final List<int> bytes = await landmarkImage.readAsBytes();
      final ({String id, String url}) uploaded = await landmarkLogic
          .uploadImage(bytes);
      _capturedImageRef = LandmarkDraftPhoto(
        id: uploaded.id,
        url: uploaded.url,
        type: _capturedImageType,
        // The signboard/stall photo's OWN fix - restored with the draft so a
        // resumed form still knows where the photo was taken.
        captureLocation: _capturedImageLocation,
      );
    }

    final XFile? primaryImage = _recognizedFoodImage;
    if (primaryImage != null && _recognizedFoodImageRef == null) {
      final List<int> bytes = await primaryImage.readAsBytes();
      final ({String id, String url}) uploaded = await landmarkLogic
          .uploadImage(bytes);
      _recognizedFoodImageRef = LandmarkDraftPhoto(
        id: uploaded.id,
        url: uploaded.url,
      );
    }

    bool changed = false;
    final List<LandmarkFoodEntry> updated = <LandmarkFoodEntry>[];
    for (final LandmarkFoodEntry entry in _additionalFoods) {
      final XFile? image = entry.image;
      if (image != null && entry.photoRef == null) {
        final List<int> bytes = await image.readAsBytes();
        final ({String id, String url}) uploaded = await landmarkLogic
            .uploadImage(bytes);
        updated.add(
          entry.withPhotoRef(
            LandmarkDraftPhoto(id: uploaded.id, url: uploaded.url),
          ),
        );
        changed = true;
      } else {
        updated.add(entry);
      }
    }
    if (changed) _additionalFoods = updated;
  }

  /// Uploads [image] to Supabase Storage and returns what the row stores for
  /// it - the object name (`image_id`) and public URL (`image_url`) - or
  /// null when there's no photo to upload. Used for both the landmark's own
  /// signboard/stall photo and each food's photo (all go to the same
  /// `landmark-images` bucket). Network lives in the repository
  /// (`LandmarkSubmissionLogic.uploadImage`); this method just reads the
  /// bytes off the XFile the capture flow produced.
  Future<({String id, String url})?> _uploadPhoto(XFile? image) async {
    if (image == null) return null;
    final List<int> bytes = await image.readAsBytes();
    return landmarkLogic.uploadImage(bytes);
  }

  /// The stored reference a row should carry for a photo: a fresh local
  /// capture is uploaded, while a resumed draft's already-uploaded photo is
  /// reused as-is (no duplicate objects). Null when there is no photo.
  Future<({String id, String url})?> _photoFor(
    XFile? image,
    LandmarkDraftPhoto? stored,
  ) async {
    final ({String id, String url})? uploaded = await _uploadPhoto(image);
    if (uploaded != null) return uploaded;
    if (stored == null) return null;
    return (id: stored.id, url: stored.url);
  }

  /// Submit landmark to database
  /// Validates: image captured, restaurant name, every food has a price,
  /// operating hours are complete/non-overlapping.
  /// [isFake] marks every food as test/QA data ("fake food") - the repository
  /// writes `[FAKE] ` into the saved dish text so the row is identifiable in
  /// Supabase (used while verifying the insert flow works).
  /// Errors: A13 (restaurant exists), A16 (price invalid), M6 (no image)
  Future<void> submitLandmark({bool isFake = false}) async {
    _submitMerged = false;
    _submitTargetName = null;
    _submitAddedDishNames = const <String>[];
    _submitExistingDishNames = const <String>[];
    if (!hasImageCaptured) {
      _submitError = 'Please capture a signboard or stall image.';
      safeNotifyListeners();
      return;
    }
    final String? nameError = restaurantNameError;
    if (nameError != null) {
      _submitError = nameError;
      safeNotifyListeners();
      return;
    }
    final String? phoneError = restaurantPhoneError;
    if (phoneError != null) {
      _submitError = phoneError;
      safeNotifyListeners();
      return;
    }
    final String? websiteError = restaurantWebsiteError;
    if (websiteError != null) {
      _submitError = websiteError;
      safeNotifyListeners();
      return;
    }
    final String? addressError = restaurantAddressError;
    if (addressError != null) {
      _submitError = addressError;
      safeNotifyListeners();
      return;
    }

    final double? primaryPrice = _primaryFood?.price;
    if (primaryPrice == null || !landmarkLogic.isValidPrice(primaryPrice)) {
      _submitError =
          'Price must be between ${landmarkLogic.priceBandRangeText}.';
      safeNotifyListeners();
      return;
    }

    // The landmark's coordinates are the pin if the tourist moved it, else
    // the capture-time location (falling back to the live fix when the
    // capture carried none). A new landmark must be on Malaysian land (A9) -
    // reject before any spinner/network work, same fail-fast style as the
    // other checks above.
    final TouristLocation location = _adjustedLocation.isKnown
        ? _adjustedLocation
        : baseLocation;
    if (location.isKnown &&
        !landmarkLogic.isOnLand(location.latitude, location.longitude)) {
      _submitError = 'New landmarks must be within Malaysia and on land.';
      safeNotifyListeners();
      return;
    }

    final bool hasIncompleteAdditionalPrice = _additionalFoods.any(
      (LandmarkFoodEntry entry) =>
          entry.price == null || !landmarkLogic.isValidPrice(entry.price!),
    );
    if (hasIncompleteAdditionalPrice) {
      _submitError =
          'Every added food needs a price between '
          '${landmarkLogic.priceBandRangeText}.';
      safeNotifyListeners();
      return;
    }

    final String? hoursError = _operatingHoursError();
    if (hoursError != null) {
      _submitError = hoursError;
      safeNotifyListeners();
      return;
    }

    // The restaurant details must have been confirmed ("Confirm" under the
    // Restaurant Name) - it is what checked the photo + name, and what
    // looked for another unfinished submission for this restaurant.
    if (!_restaurantConfirmed) {
      _submitError = _confirmRestaurantReason;
      safeNotifyListeners();
      return;
    }

    _isSubmitting = true;
    _submitError = null;
    safeNotifyListeners();

    try {
      // The optional website field gets a STRICT reachability check (HTTP
      // 200-399 within 5s) before anything is uploaded/saved. Best-effort
      // from the client for form validation; production should move this to
      // the backend (SSRF).
      if (_website.trim().isNotEmpty &&
          !await landmarkLogic.isWebsiteReachable(_website)) {
        // Surface the finding under the field as well, so the submit error
        // and the live status agree.
        _websiteLinkUnreachable = true;
        _submitError = _websiteUnreachableMessage;
        _isSubmitting = false;
        safeNotifyListeners();
        return;
      }
      // The signed-in tourist - null when nobody is signed in (the entry
      // gate routes to sign-in first, so a signed-in tourist is expected
      // here).
      final String? touristId = await landmarkLogic.currentTouristId();
      if (touristId == null || touristId.isEmpty) {
        throw StateError(_signInRequiredMessage);
      }

      // Upload the landmark's own signboard/stall photo FIRST - it is stored
      // on the `submitted_landmark` row (`image_url` / `image_id` /
      // `image_category`), same bucket as the food photos. A photo carried
      // over from a resumed draft is reused, not re-uploaded.
      final ({String id, String url})? landmarkPhoto = await _photoFor(
        _capturedImage,
        _capturedImageRef,
      );

      // Upload each food's photo to Supabase Storage NEXT - the resulting
      // object name + public URL are what `landmark_item.image_id` /
      // `landmark_item.image_url` store. A food without a photo stays null
      // in those columns.
      final ({String id, String url})? primaryPhoto = await _photoFor(
        _recognizedFoodImage,
        _recognizedFoodImageRef,
      );
      final List<({String id, String url})?> additionalPhotos =
          <({String id, String url})?>[];
      for (final LandmarkFoodEntry entry in _additionalFoods) {
        additionalPhotos.add(await _photoFor(entry.image, entry.photoRef));
      }

      // Everything below is raw, already-validated form data - building the
      // actual SubmittedLandmark/LandmarkItem domain objects (and deciding
      // their defaults, like reportedCount: 0 and status: available) is
      // LandmarkSubmissionLogic's job now, not this ViewModel's - see that
      // method's doc for why.
      final result = await landmarkLogic.submitLandmark(
        restaurantName: _restaurantName,
        latitude: location.isKnown ? location.latitude : null,
        longitude: location.isKnown ? location.longitude : null,
        category: _primaryFood!.food.category,
        touristId: touristId,
        imageUrl: landmarkPhoto?.url,
        imageId: landmarkPhoto?.id,
        imageCategory: _capturedImageType,
        phone: _phone.trim(),
        website: _website.trim(),
        address: _address.trim(),
        foods: <FoodSubmission>[
          FoodSubmission(
            food: _primaryFood!.food,
            price: _primaryFood!.price!,
            isFake: isFake,
            priceMin: _primaryFood!.priceMin,
            priceMax: _primaryFood!.priceMax,
            imageUrl: primaryPhoto?.url,
            imageId: primaryPhoto?.id,
            confidence: _recognizedFoodConfidence,
            isLocalFood: true,
            variant: _recognizedFoodVariant,
            dietaryRestrictions: _recognizedFoodDietaryRestrictions,
          ),
          for (int i = 0; i < _additionalFoods.length; i++)
            FoodSubmission(
              food: _additionalFoods[i].food,
              price: _additionalFoods[i].price!,
              isFake: isFake,
              priceMin: _additionalFoods[i].priceMin,
              priceMax: _additionalFoods[i].priceMax,
              imageUrl: additionalPhotos[i]?.url,
              imageId: additionalPhotos[i]?.id,
              variant: _additionalFoods[i].variant,
              dietaryRestrictions: _additionalFoods[i].dietaryRestrictions,
            ),
        ],
        operatingHours: _operatingHours,
        overwriteExistingDetails: _overwriteExistingDetails ?? false,
      );
      _submitMerged = result.merged;
      _submitTargetName = result.targetName;
      _submitAddedDishNames = List<String>.of(result.addedDishNames);
      _submitExistingDishNames = List<String>.of(result.existingDishNames);

      // The landmark is saved - the incomplete submission it may have come
      // from is done. Only the draft ROW is removed; its photos stay because
      // the landmark now stores those same objects.
      await clearSubmittedDraft();

      _isSubmitting = false;
      safeNotifyListeners();
    } catch (error) {
      _submitError = _submitFailureMessage(error);
      _isSubmitting = false;
      safeNotifyListeners();
    }
  }

  /// User-safe copy for a failed submit. Raw exception text
  /// (`PostgrestException(...)`, `Bad state: ...`, socket errors) must never
  /// reach the form; only messages the APP itself authors pass through -
  /// the sign-in requirement and the local-food origin verifier's verdict
  /// (see [LandmarkLogicFacade.landmarkVerificationRejectionMessage]).
  String _submitFailureMessage(Object error) {
    if (error is StateError && error.message == _signInRequiredMessage) {
      return _signInRequiredMessage;
    }
    final String? rejection = landmarkLogic
        .landmarkVerificationRejectionMessage(error);
    if (rejection != null && rejection.isNotEmpty) return rejection;
    return 'Something went wrong while submitting. Please check your '
        'connection and try again.';
  }

  @override
  void dispose() {
    _websiteLinkDebounce?.cancel();
    _mapAddressDebounce?.cancel();
    _addressSearchDebounce?.cancel();
    locationFacade.unregister(this);
    super.dispose();
  }
}
