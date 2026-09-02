import 'package:image_picker/image_picker.dart';

import '../app/routing/app_navigator.dart';
import '../app/routing/app_routes.dart';
import '../core/base_view_model.dart';
import '../domain_model/local_food.dart';
import '../domain_model/opening_hour.dart';
import '../domain_model/submitted_landmark.dart';
import '../domain_model/tourist_location.dart';
import '../model/business_logic/landmark_logic_facade.dart';
import 'current_location_facade.dart';
import 'food_recognition_view_model.dart'
    show
        AdditionalFoodCaptureResult,
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
    this.price,
    this.priceMin = 0,
    this.priceMax = 0,
  });

  /// Creates a new form entry with a fresh, form-local identity.
  factory LandmarkFoodEntry.newEntry({
    required LocalFood food,
    XFile? image,
    double? price,
    double priceMin = 0,
    double priceMax = 0,
  }) => LandmarkFoodEntry._(
    entryId: _nextEntryId++,
    food: food,
    image: image,
    price: price,
    priceMin: priceMin,
    priceMax: priceMax,
  );

  static int _nextEntryId = 0;

  final int entryId;
  final LocalFood food;

  /// This food's own photo, as captured on `FoodRecognitionView` - only
  /// ever set for additional foods (see `AddLandmarkViewModel.addAdditionalFood`).
  /// The primary food's photo is tracked separately, via
  /// `AddLandmarkViewModel._recognizedFoodImage` - not duplicated here.
  final XFile? image;
  final double? price;

  /// Gemini's suggested MYR price range for this food, carried onto the
  /// persisted `LandmarkItem`. `0` means unknown.
  final double priceMin;
  final double priceMax;

  LandmarkFoodEntry withPrice(double newPrice) => LandmarkFoodEntry._(
    entryId: entryId,
    food: food,
    image: image,
    price: newPrice,
    priceMin: priceMin,
    priceMax: priceMax,
  );

  LandmarkFoodEntry withFood(LocalFood newFood) => LandmarkFoodEntry._(
    entryId: entryId,
    food: newFood,
    image: image,
    price: price,
    priceMin: priceMin,
    priceMax: priceMax,
  );

  LandmarkFoodEntry withPriceRange({
    required double priceMin,
    required double priceMax,
  }) => LandmarkFoodEntry._(
    entryId: entryId,
    food: food,
    image: image,
    price: price,
    priceMin: priceMin,
    priceMax: priceMax,
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
  AddLandmarkViewModel();

  final LandmarkLogicFacade landmarkLogic = LandmarkLogicFacade();

  /// Inbound: `LocationMonitor` publishes here.
  final CurrentLocationFacade locationFacade = CurrentLocationFacade();

  @override
  Future<void> onInit() async {
    locationFacade.register(this);
  }

  // --- LOCATION STATE ---
  TouristLocation _currentLocation = TouristLocation.unknown;
  TouristLocation _adjustedLocation = TouristLocation.unknown;

  /// Pushed by `LocationMonitor` through [CurrentLocationFacade].
  @override
  void onCurrentLocationChanged(TouristLocation location) {
    _currentLocation = location;
    safeNotifyListeners();
  }

  String? _locationError;

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
  List<LandmarkFoodEntry> _additionalFoods = <LandmarkFoodEntry>[];

  /// Per-entry soft price guidance, keyed by the form-local
  /// [LandmarkFoodEntry.entryId].
  final Map<int, String> _additionalFoodPriceWarnings = <int, String>{};

  // --- IMAGE CAPTURE STATE (MANDATORY - ONE of two) ---
  XFile? _capturedImage; // Either signboard or stall
  String? _capturedImageType; // 'signboard' or 'stall'
  bool _isSignboardDisabled = false; // True after stall captured
  bool _isStallDisabled = false; // True after signboard captured

  // --- FORM STATE ---
  String _restaurantName = '';

  /// Bumped by [setExtractedRestaurantName] whenever a signboard capture
  /// overwrites [_restaurantName]. `AddLandmarkView` compares this to the
  /// version it last applied to its text field to tell a fresh signboard
  /// result (which must overwrite the tourist's typed name) apart from the
  /// tourist's own typing (which must not fight the field).
  int _extractedRestaurantNameVersion = 0;

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

  // --- SUBMISSION STATE ---
  bool _isSubmitting = false;
  String? _submitError;

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

  LocalFood? get recognizedFood => _primaryFood?.food;
  XFile? get recognizedFoodImage => _recognizedFoodImage;
  double? get primaryFoodPrice => _primaryFood?.price;
  String? get primaryFoodPriceWarning => _primaryFoodPriceWarning;
  String? additionalFoodPriceWarning(int entryId) =>
      _additionalFoodPriceWarnings[entryId];
  List<LandmarkFoodEntry> get additionalFoods =>
      List<LandmarkFoodEntry>.unmodifiable(_additionalFoods);

  XFile? get capturedImage => _capturedImage;
  String? get capturedImageType => _capturedImageType;
  bool get hasImageCaptured => _capturedImage != null;
  bool get isSignboardDisabled => _isSignboardDisabled;
  bool get isStallDisabled => _isStallDisabled;

  String get restaurantName => _restaurantName;

  /// See [_extractedRestaurantNameVersion].
  int get extractedRestaurantNameVersion => _extractedRestaurantNameVersion;

  Map<Weekday, List<OpeningHour>> get operatingHours =>
      Map<Weekday, List<OpeningHour>>.unmodifiable(_operatingHours);

  bool get isSubmitting => _isSubmitting;
  String? get submitError => _submitError;

  /// Whether the last successful submit merged into an existing place
  /// instead of creating a new landmark.
  bool get submitMerged => _submitMerged;

  /// Confirmation copy for a MERGED submit (A13) - says which dishes were
  /// added and which already existed on the target, so the tourist sees
  /// "item exists" honestly. Null when a new landmark was created (the View
  /// shows the default success message instead). Name lists are capped so an
  /// open-ended number of dishes can never overflow the snackbar.
  String? get submitConfirmation {
    if (!_submitMerged) return null;
    final String rawTarget =
        (_submitTargetName == null || _submitTargetName!.isEmpty)
        ? 'this place'
        : '"${_truncate(_submitTargetName!)}"';
    final List<String> added = _previewNames(_submitAddedDishNames);
    final List<String> existing = _previewNames(_submitExistingDishNames);
    final String head;
    if (added.isNotEmpty && existing.isNotEmpty) {
      head =
          'Added ${added.join(', ')}. '
          'Already exists: ${existing.join(', ')}.';
    } else if (existing.isNotEmpty) {
      head = '${existing.join(', ')} already exists - nothing new added.';
    } else if (added.isNotEmpty) {
      head = 'Added ${added.join(', ')}.';
    } else {
      head = 'Dishes added.';
    }
    return '$head ($rawTarget)'.replaceAll('  ', ' ');
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
      _capturedImage != null &&
      _restaurantName.isNotEmpty &&
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
    if (_capturedImage == null) {
      return 'Please capture either signboard or stall image';
    }
    if (_restaurantName.isEmpty) {
      return 'Restaurant name is required';
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
    return _operatingHoursError();
  }

  // --- COMMANDS ---

  /// Set recognized food (auto-filled from food recognition, or from
  /// `LandmarkDraftHandoff` before `onInit()` - see class doc). Keeps any
  /// price already entered for this food if it is set again.
  void setRecognizedFood(
    LocalFood food, {
    double priceMin = 0,
    double priceMax = 0,
    double confidence = 0,
    List<String> dietaryRestrictions = const <String>[],
  }) {
    _recognizedFoodConfidence = confidence;
    _recognizedFoodDietaryRestrictions = dietaryRestrictions;
    _primaryFood = _primaryFood == null
        ? LandmarkFoodEntry.newEntry(
            food: food,
            priceMin: priceMin,
            priceMax: priceMax,
          )
        : _primaryFood!
              .withFood(food)
              .withPriceRange(priceMin: priceMin, priceMax: priceMax);
    // The previous food's suggested range no longer applies.
    _primaryFoodPriceWarning = null;
    safeNotifyListeners();
  }

  /// Set the primary food's photo - see `_recognizedFoodImage`.
  void setRecognizedFoodImage(XFile image) {
    _recognizedFoodImage = image;
    safeNotifyListeners();
  }

  /// Set the price for the primary (recognized) food. (A16)
  void setPrimaryFoodPrice(double price) {
    if (_primaryFood == null) return;
    if (!landmarkLogic.isValidPrice(price)) {
      _submitError = 'Price must be between 0.01 and 1000 MYR';
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
  /// tourist may correct the pin - but only within 100m of the current fix
  /// (A9.1). Beyond that, the change is rejected and the pin reverts to its
  /// last valid position; nothing here is mutated.
  void adjustLandmarkLocation(double latitude, double longitude) {
    if (!landmarkLogic.isWithinAllowedRange(
      currentLocation,
      latitude,
      longitude,
    )) {
      _locationError = 'The adjusted landmark exceeds 100 meters range.'; // M9
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
    safeNotifyListeners();
  }

  /// Opens `FoodRecognitionView` in signboard-capture mode and waits for its
  /// result. This screen stays on the stack the whole time - the result
  /// comes back through the pushed route's own `Future<T?>`, not a hand-off.
  Future<void> openSignboardCapture() async {
    LandmarkDraftHandoff().pendingPurpose = FoodRecognitionPurpose.signboard;
    final LandmarkImageCaptureResult? result =
        await AppNavigator.push<LandmarkImageCaptureResult>(
          AppRoutes.foodRecognition,
        );
    if (result == null) return; // Tourist backed out without confirming.

    setCapturedImage(result.image, result.imageType);
    if (result.extractedRestaurantName != null) {
      setExtractedRestaurantName(result.extractedRestaurantName);
    }
  }

  /// Same as [openSignboardCapture], in stall-capture mode - no auto-fill.
  Future<void> openStallCapture() async {
    LandmarkDraftHandoff().pendingPurpose = FoodRecognitionPurpose.stall;
    final LandmarkImageCaptureResult? result =
        await AppNavigator.push<LandmarkImageCaptureResult>(
          AppRoutes.foodRecognition,
        );
    if (result == null) return;

    setCapturedImage(result.image, result.imageType);
  }

  /// Set captured image (signboard or stall)
  /// Automatically disables the other button
  void setCapturedImage(XFile image, String imageType) {
    _capturedImage = image;
    _capturedImageType = imageType;

    if (imageType == 'signboard') {
      _isStallDisabled = true; // Can't capture stall after signboard
    } else if (imageType == 'stall') {
      _isSignboardDisabled = true; // Can't capture signboard after stall
    }
    safeNotifyListeners();
  }

  /// Cancels the captured signboard/stall image (the "x" next to it) -
  /// clears it entirely and re-enables both capture buttons. Distinct from
  /// "Retake" (which keeps the mutual-exclusion lock and just re-opens the
  /// same capture mode) - this undoes the choice altogether. Doesn't touch
  /// `_restaurantName` even if it was auto-filled from a signboard - the
  /// tourist may still want to keep that.
  void clearCapturedImage() {
    _capturedImage = null;
    _capturedImageType = null;
    _isSignboardDisabled = false;
    _isStallDisabled = false;
    safeNotifyListeners();
  }

  /// Set extracted restaurant name (from signboard capture only).
  /// Overwrites whatever the tourist typed - the signboard is authoritative,
  /// and they can edit it afterwards. Bumps [_extractedRestaurantNameVersion]
  /// so `AddLandmarkView` can force its text field to show this name even
  /// while the field is still focused (the focus-guarded sync alone would
  /// skip it, leaving the tourist's typed name on screen).
  void setExtractedRestaurantName(String? name) {
    if (name != null && name.trim().isNotEmpty) {
      _restaurantName = name.trim();
      _extractedRestaurantNameVersion++;
      safeNotifyListeners();
    }
  }

  /// Manually set restaurant name (user types)
  void setRestaurantName(String name) {
    _restaurantName = name.trim();
    safeNotifyListeners();
  }

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
    final int? closing = isOpeningTime ? row.closesAt : minutes;

    // If the pick would make this range invalid, ignore it and keep the
    // previous value - stops a confusing "closing must be after opening"
    // error from appearing at submit time. The rule itself
    // (`isValidTimeOrder`) lives in `LandmarkSubmissionLogic`, the same
    // domain invariant `validateOperatingHours` checks across a whole day -
    // not reimplemented inline here.
    if (opening != null &&
        closing != null &&
        !landmarkLogic.isValidTimeOrder(opening, closing)) {
      return;
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
  /// this food's card, same as the primary food.
  Future<void> openAddMoreFood() async {
    LandmarkDraftHandoff().pendingPurpose =
        FoodRecognitionPurpose.additionalFood;
    final AdditionalFoodCaptureResult? result =
        await AppNavigator.push<AdditionalFoodCaptureResult>(
          AppRoutes.foodRecognition,
        );
    if (result == null) return; // Tourist backed out without confirming.
    addAdditionalFood(
      result.food,
      image: result.image,
      priceMin: result.priceMin,
      priceMax: result.priceMax,
    );
  }

  /// Add additional food directly (used when the food is already in hand -
  /// prefer [openAddMoreFood] from the View).
  void addAdditionalFood(
    LocalFood food, {
    XFile? image,
    double priceMin = 0,
    double priceMax = 0,
  }) {
    _additionalFoods = <LandmarkFoodEntry>[
      ..._additionalFoods,
      LandmarkFoodEntry.newEntry(
        food: food,
        image: image,
        priceMin: priceMin,
        priceMax: priceMax,
      ),
    ];
    safeNotifyListeners();
  }

  /// Set the price for one additional food, by its form-local [entryId] -
  /// NOT `LocalFood.id`, which is `0` for every unsaved food. (A16)
  void setAdditionalFoodPrice(int entryId, double price) {
    if (!landmarkLogic.isValidPrice(price)) {
      _submitError = 'Price must be between 0.01 and 1000 MYR';
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
      _submitError = 'Please capture either signboard or stall image';
      safeNotifyListeners();
      return;
    }
    if (_restaurantName.isEmpty) {
      _submitError = 'Restaurant name is required';
      safeNotifyListeners();
      return;
    }

    final double? primaryPrice = _primaryFood?.price;
    if (primaryPrice == null || !landmarkLogic.isValidPrice(primaryPrice)) {
      _submitError = 'Price must be between 0.01 and 1000 MYR';
      safeNotifyListeners();
      return;
    }

    // The landmark's coordinates are the pin if the tourist moved it, else
    // the raw GPS fix. A new landmark must be on Malaysian land (A9) - reject
    // before any spinner/network work, same fail-fast style as the other
    // checks above.
    final TouristLocation location = _adjustedLocation.isKnown
        ? _adjustedLocation
        : currentLocation;
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
      _submitError = 'Every added food needs a price between 0.01 and 1000 MYR';
      safeNotifyListeners();
      return;
    }

    final String? hoursError = _operatingHoursError();
    if (hoursError != null) {
      _submitError = hoursError;
      safeNotifyListeners();
      return;
    }

    _isSubmitting = true;
    _submitError = null;
    safeNotifyListeners();

    try {
      // The signed-in tourist - null when nobody is signed in (the entry
      // gate routes to sign-in first, so a signed-in tourist is expected
      // here).
      final String? touristId = await landmarkLogic.currentTouristId();
      if (touristId == null || touristId.isEmpty) {
        throw StateError('Sign in to submit a landmark.');
      }

      // Upload the landmark's own signboard/stall photo FIRST - it is stored
      // on the `submitted_landmark` row (`image_url` / `image_id` /
      // `image_category`), same bucket as the food photos.
      final ({String id, String url})? landmarkPhoto = _capturedImage == null
          ? null
          : await _uploadPhoto(_capturedImage);

      // Upload each food's photo to Supabase Storage NEXT - the resulting
      // object name + public URL are what `landmark_item.image_id` /
      // `landmark_item.image_url` store. A food without a photo stays null
      // in those columns.
      final ({String id, String url})? primaryPhoto = await _uploadPhoto(
        _recognizedFoodImage,
      );
      final List<({String id, String url})?> additionalPhotos =
          <({String id, String url})?>[];
      for (final LandmarkFoodEntry entry in _additionalFoods) {
        additionalPhotos.add(await _uploadPhoto(entry.image));
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
            ),
        ],
        operatingHours: _operatingHours,
      );
      _submitMerged = result.merged;
      _submitTargetName = result.targetName;
      _submitAddedDishNames = List<String>.of(result.addedDishNames);
      _submitExistingDishNames = List<String>.of(result.existingDishNames);

      _isSubmitting = false;
      safeNotifyListeners();
    } catch (e) {
      _submitError = e.toString();
      _isSubmitting = false;
      safeNotifyListeners();
    }
  }

  @override
  void dispose() {
    locationFacade.unregister(this);
    super.dispose();
  }
}
