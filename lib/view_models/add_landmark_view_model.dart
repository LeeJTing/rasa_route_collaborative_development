import 'package:image_picker/image_picker.dart';

import '../app/routing/app_navigator.dart';
import '../app/routing/app_routes.dart';
import '../core/base_view_model.dart';
import '../domain_model/local_food.dart';
import '../domain_model/opening_hour.dart';
import '../domain_model/submitted_landmark.dart';
import '../model/business_logic/landmark_logic_facade.dart';
import '../model/data_models/location_data_model.dart';
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
  });

  /// Creates a new form entry with a fresh, form-local identity.
  factory LandmarkFoodEntry.newEntry({
    required LocalFood food,
    XFile? image,
    double? price,
  }) => LandmarkFoodEntry._(
    entryId: _nextEntryId++,
    food: food,
    image: image,
    price: price,
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

  LandmarkFoodEntry withPrice(double newPrice) => LandmarkFoodEntry._(
    entryId: entryId,
    food: food,
    image: image,
    price: newPrice,
  );

  LandmarkFoodEntry withFood(LocalFood newFood) => LandmarkFoodEntry._(
    entryId: entryId,
    food: newFood,
    image: image,
    price: price,
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

  /// Pushed by `LocationMonitor` through [CurrentLocationFacade].
  @override
  void onCurrentLocationChanged(LocationDataModel location) {
    _currentLocation = location;
    safeNotifyListeners();
  }

  // --- LOCATION STATE ---
  LocationDataModel _currentLocation = LocationDataModel.unknown;
  LocationDataModel _adjustedLocation = LocationDataModel.unknown;
  String? _locationError;

  // --- FOOD STATE (auto-filled from recognition; price entered per food) ---
  LandmarkFoodEntry? _primaryFood;

  /// The primary food's own photo (as captured on `FoodRecognitionView`),
  /// carried here via `LandmarkDraftHandoff.pendingCapturedImage` so the
  /// "Recognised Food" card can show the same thumbnail the tourist saw
  /// there - see [setRecognizedFoodImage].
  XFile? _recognizedFoodImage;
  List<LandmarkFoodEntry> _additionalFoods = <LandmarkFoodEntry>[];

  // --- IMAGE CAPTURE STATE (MANDATORY - ONE of two) ---
  XFile? _capturedImage; // Either signboard or stall
  String? _capturedImageType; // 'signboard' or 'stall'
  bool _isSignboardDisabled = false; // True after stall captured
  bool _isStallDisabled = false; // True after signboard captured

  // --- FORM STATE ---
  String _restaurantName = '';

  /// Every weekday always has at least one row here. A Closed/Unknown day
  /// has exactly one row (times null); an Open day can have more than one
  /// - matching the real `OpeningHours` table directly, where each row is
  /// independently `(day, status, opening_time, closing_time)`, not a
  /// day-level wrapper around a list.
  Map<Weekday, List<OpeningHour>> _operatingHours =
      <Weekday, List<OpeningHour>>{
        for (final Weekday day in Weekday.values)
          day: <OpeningHour>[
            OpeningHour(id: 0, day: day, status: DayStatus.closed),
          ],
      };

  // --- SUBMISSION STATE ---
  bool _isSubmitting = false;
  String? _submitError;

  // --- GETTERS ---
  LocationDataModel get currentLocation => _currentLocation;
  LocationDataModel get adjustedLocation => _adjustedLocation;
  String? get locationError => _locationError;

  LocalFood? get recognizedFood => _primaryFood?.food;
  XFile? get recognizedFoodImage => _recognizedFoodImage;
  double? get primaryFoodPrice => _primaryFood?.price;
  List<LandmarkFoodEntry> get additionalFoods =>
      List<LandmarkFoodEntry>.unmodifiable(_additionalFoods);

  XFile? get capturedImage => _capturedImage;
  String? get capturedImageType => _capturedImageType;
  bool get hasImageCaptured => _capturedImage != null;
  bool get isSignboardDisabled => _isSignboardDisabled;
  bool get isStallDisabled => _isStallDisabled;

  String get restaurantName => _restaurantName;
  Map<Weekday, List<OpeningHour>> get operatingHours =>
      Map<Weekday, List<OpeningHour>>.unmodifiable(_operatingHours);

  bool get isSubmitting => _isSubmitting;
  String? get submitError => _submitError;

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
  void setRecognizedFood(LocalFood food) {
    _primaryFood = _primaryFood == null
        ? LandmarkFoodEntry.newEntry(food: food)
        : _primaryFood!.withFood(food);
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
    if (!landmarkLogic.submission.isValidPrice(price)) {
      _submitError = 'Price must be between 0.01 and 1000 MYR';
      safeNotifyListeners();
      return;
    }
    _primaryFood = _primaryFood!.withPrice(price);
    _submitError = null;
    safeNotifyListeners();
  }

  /// Adjust map pin location (user drags pin). GPS can be inaccurate, so the
  /// tourist may correct the pin - but only within 100m of the current fix
  /// (A9.1). Beyond that, the change is rejected and the pin reverts to its
  /// last valid position; nothing here is mutated.
  void adjustLandmarkLocation(double latitude, double longitude) {
    if (!landmarkLogic.submission.isWithinAllowedRange(
      _currentLocation,
      latitude,
      longitude,
    )) {
      _locationError = 'The adjusted landmark exceeds 100 meters range.'; // M9
      safeNotifyListeners();
      return; // Revert: _adjustedLocation is left unchanged.
    }

    _locationError = null;
    _adjustedLocation = LocationDataModel(
      latitude: latitude,
      longitude: longitude,
      accuracyMeters: _currentLocation.accuracyMeters,
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

  /// Set extracted restaurant name (from signboard capture only)
  void setExtractedRestaurantName(String? name) {
    if (name != null && name.isNotEmpty) {
      _restaurantName = name;
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

    // Guard: a row is a single (open, close) range, so never store a closing
    // time at/before its opening (or an opening at/after its closing). If
    // the pick would make closing <= opening, ignore it and keep the previous
    // value - this stops a confusing "closing must be after opening" error
    // from appearing at submit time.
    if (opening != null && closing != null && closing <= opening) return;

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
    addAdditionalFood(result.food, image: result.image);
  }

  /// Add additional food directly (used when the food is already in hand -
  /// prefer [openAddMoreFood] from the View).
  void addAdditionalFood(LocalFood food, {XFile? image}) {
    _additionalFoods = <LandmarkFoodEntry>[
      ..._additionalFoods,
      LandmarkFoodEntry.newEntry(food: food, image: image),
    ];
    safeNotifyListeners();
  }

  /// Set the price for one additional food, by its form-local [entryId] -
  /// NOT `LocalFood.id`, which is `0` for every unsaved food. (A16)
  void setAdditionalFoodPrice(int entryId, double price) {
    if (!landmarkLogic.submission.isValidPrice(price)) {
      _submitError = 'Price must be between 0.01 and 1000 MYR';
      safeNotifyListeners();
      return;
    }
    _additionalFoods = _additionalFoods
        .map(
          (LandmarkFoodEntry entry) =>
              entry.entryId == entryId ? entry.withPrice(price) : entry,
        )
        .toList(growable: false);
    _submitError = null;
    safeNotifyListeners();
  }

  /// Remove additional food, by its form-local [entryId].
  void removeAdditionalFood(int entryId) {
    _additionalFoods = _additionalFoods
        .where((LandmarkFoodEntry entry) => entry.entryId != entryId)
        .toList(growable: false);
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
    return landmarkLogic.submission.validateOperatingHours(_operatingHours);
  }

  /// Submit landmark to database
  /// Validates: image captured, restaurant name, every food has a price,
  /// operating hours are complete/non-overlapping.
  /// [isFake] marks every food as test/QA data ("fake food") - the repository
  /// writes `[FAKE] ` into the saved dish text so the row is identifiable in
  /// Supabase (used while verifying the insert flow works).
  /// Errors: A13 (restaurant exists), A16 (price invalid), M6 (no image)
  Future<void> submitLandmark({bool isFake = false}) async {
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
    if (primaryPrice == null ||
        !landmarkLogic.submission.isValidPrice(primaryPrice)) {
      _submitError = 'Price must be between 0.01 and 1000 MYR';
      safeNotifyListeners();
      return;
    }

    final bool hasIncompleteAdditionalPrice = _additionalFoods.any(
      (LandmarkFoodEntry entry) =>
          entry.price == null ||
          !landmarkLogic.submission.isValidPrice(entry.price!),
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
      final String? touristId = await landmarkLogic.submission
          .currentTouristId();
      if (touristId == null) {
        _submitError =
            'Unable to identify tourist session. Please sign in again.';
        _isSubmitting = false;
        safeNotifyListeners();
        return;
      }

      final LocationDataModel location = _adjustedLocation.isKnown
          ? _adjustedLocation
          : _currentLocation;

      // Everything below is raw, already-validated form data - building the
      // actual SubmittedLandmark/LandmarkItem domain objects (and deciding
      // their defaults, like reportedCount: 0 and status: pending) is
      // LandmarkSubmissionLogic's job now, not this ViewModel's - see that
      // method's doc for why (and for the signboard/stall photo gap, which
      // is unrelated to this refactor and still open).
      await landmarkLogic.submission.submitLandmark(
        restaurantName: _restaurantName,
        latitude: location.isKnown ? location.latitude : null,
        longitude: location.isKnown ? location.longitude : null,
        category: _primaryFood!.food.category,
        touristId: touristId,
        foods: <FoodSubmission>[
          FoodSubmission(
            food: _primaryFood!.food,
            price: _primaryFood!.price!,
            isFake: isFake,
          ),
          for (final LandmarkFoodEntry entry in _additionalFoods)
            FoodSubmission(
              food: entry.food,
              price: entry.price!,
              isFake: isFake,
            ),
        ],
        operatingHours: _operatingHours,
      );

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
