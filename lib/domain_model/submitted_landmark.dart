import 'local_food.dart';
import 'opening_hour.dart';

/// A food landmark contributed by a tourist, plus the dishes attached to it.
///
/// Domain models are plain data types. They carry no JSON - serialisation is
/// the data model's job in `lib/model/data_models/`, and the repository is what
/// converts a data model into one of these. They travel upward unchanged from
/// repository to logic to ViewModel to View.
class SubmittedLandmark {
  const SubmittedLandmark({
    required this.id,
    required this.name,
    this.latitude,
    this.longitude,
    required this.category,
    required this.reportedCount,
    required this.status,
    this.imageUrl,
    this.imageId,
    this.imageCategory,
    this.phone = '',
    this.website = '',
    this.address = '',
    required this.items,
    required this.openingHours,
  });

  final int id;
  final String name;
  final double? latitude;
  final double? longitude;
  final String category;
  final int reportedCount;
  final LandmarkStatus status;

  /// The landmark's own signboard/stall photo, uploaded to Supabase Storage
  /// (`landmark-images` bucket) and persisted on `submitted_landmark`
  /// (`image_url` / `image_id` / `image_category` - all text). Null when no
  /// image was captured.
  final String? imageUrl;
  final String? imageId;

  /// What kind of photo [imageUrl]/[imageId] is - `'signboard'` or `'stall'`
  /// (see `AddLandmarkViewModel._capturedImageType`).
  final String? imageCategory;

  /// Optional tourist-supplied contact/address for the place, collected on
  /// the Add New Landmark form and persisted on `submitted_landmark`
  /// (`phone` / `website` / `address`). Empty string when not provided.
  ///
  /// Written when a BRAND-NEW landmark row is created, and on a merge into an
  /// existing submitted landmark only for fields the re-submission actually
  /// changed (see `SubmittedLandmarkRepository.changedContactFields`) - an
  /// emptier second submission never blanks data an earlier one stored. A
  /// merge into a catalogue restaurant keeps that place's own curated data
  /// (no submitted row exists to hold tourist contact details).
  final String phone;
  final String website;
  final String address;

  final List<LandmarkItem> items;
  final List<OpeningHour> openingHours;
}

/// Moderation state of a submission - `submitted_landmark.status` is free
/// text in Supabase holding one of these two values:
///   * [available] - the landmark is listed/visible to tourists;
///   * [frozen] - the landmark has been reported too many times and is
///     temporarily hidden, until it is reactivated (A20).
/// A brand-new submission is ALWAYS [available] with `reported_count` 0 (see
/// `LandmarkSubmissionLogic.submitLandmark` / `SubmittedLandmarkRepository`).
enum LandmarkStatus { available, frozen }

/// A dish attached to a submitted landmark.
///
/// Domain models are plain data types. They carry no JSON - serialisation is
/// the data model's job in `lib/model/data_models/`, and the repository is what
/// converts a data model into one of these. They travel upward unchanged from
/// repository to logic to ViewModel to View.
class LandmarkItem {
  const LandmarkItem({
    required this.id,
    required this.landmarkId,
    required this.touristId,
    this.localFoodId = 0,
    required this.dish,
    required this.variant,
    required this.foodCategory,
    required this.description,
    required this.origin,
    required this.culturalBackground,
    this.ingredients = '',
    this.dietaryRestrictions = const <String>[],
    this.imageUrl,
    this.imageId,
    this.price,
    this.priceMin = 0,
    this.priceMax = 0,
    required this.seasonal,
    required this.cookingStyle,
    required this.mealType,
    this.isRemoved = false,
    this.isFake = false,
  });

  final int id;
  final int landmarkId;
  final String touristId;

  /// The curated `local_food` row this dish resolves to (mirrors
  /// `restaurant_item.local_food_id`). `0` when there is no catalogue row
  /// yet - a brand-new food gets its id backfilled after the Option-C
  /// catalogue insert, and an unmatched dish stays 0 (the map then falls
  /// back to name matching).
  final int localFoodId;

  final String dish;

  /// The name this dish was actually recognised/typed as, when it EXTENDS
  /// the dictionary dish name into an unlisted variant - e.g. dish `Cendol`
  /// with variant `Cendol Jagung`. Empty when the name IS the dish (its
  /// name/synonym/same words reordered). This is the landmark's record of
  /// the VARIANT; `local_food` keeps only the canonical dish.
  final String variant;

  /// The name to SHOW for this item: the [variant] the tourist actually
  /// photographed/typed when one was recorded ("Cendol Jagung"), else the
  /// dictionary [dish]. The landmark lists what was captured, not the
  /// canonical row it links to - the same label rule the draft list and the
  /// continue prompt use.
  String get displayName => variant.trim().isNotEmpty ? variant.trim() : dish;

  final String foodCategory;
  final String description;
  final String origin;
  final String culturalBackground;

  /// The item's ingredients: the dictionary row's own ingredients with the
  /// recognition's observation merged in - so a variant ("Cendol Jagung")
  /// keeps the dish's canonical facts AND gains what makes it that variant
  /// ("..., sweet corn"). Whichever side has text stands alone when the
  /// other has none; empty when neither has anything.
  final String ingredients;

  /// Canonical dietary-restriction names that apply to THIS item (e.g.
  /// `['Contains Coconut']`). For a matched dictionary dish with a fresh
  /// observation these are the OBSERVED tags; otherwise the dictionary
  /// row's own links. Persisted as one comma-separated `text` column
  /// (`landmark_item.dietary_restrictions`).
  final List<String> dietaryRestrictions;

  /// The food's own photo (as captured on `FoodRecognitionView`), stored in
  /// Supabase Storage (`landmark-images` bucket) by
  /// `SubmittedLandmarkRepository.uploadImage` before the item is
  /// inserted. Null when the food had no photo (e.g. name-typed) - the
  /// repository then writes null.
  ///
  /// `image_id` in `landmark_item` is `text` (a storage object id) - not an
  /// integer, matching the real Supabase column.
  final String? imageUrl;
  final String? imageId;
  final double? price;

  /// Suggested selling price range for this dish (MYR), from Gemini's full
  /// analysis of the recognised food. `0` means unknown. Persisted with the
  /// landmark item (`landmark_item.price_min` / `price_max`) - this is what
  /// the tourist's submission carries, NOT the shared `local_food` catalogue.
  final double priceMin;
  final double priceMax;

  final String seasonal;
  final String cookingStyle;
  final String mealType;

  /// Soft-removal flag (`landmark_item.is_removed`) - set when enough
  /// tourists reported this dish does not exist. Removed dishes are excluded
  /// from the place detail and the report picker.
  final bool isRemoved;

  /// Test/QA marker - `true` for "fake food" added while verifying the
  /// Supabase insert flow. No dedicated column exists in the real
  /// `landmark_item` table, so the repository writes the marker into the
  /// saved dish text (`[FAKE] ...`) to keep test rows identifiable.
  final bool isFake;
}

/// One food being submitted with a landmark - a food (already recognized)
/// and the price the tourist entered for it. Built by
/// `AddLandmarkViewModel`, resolved into a `LandmarkItem` by
/// `LandmarkSubmissionLogic.submitLandmark` - lighter than the ViewModel's
/// own `LandmarkFoodEntry` (no form-local id or captured image - Logic
/// doesn't need either to build a `LandmarkItem`).
class FoodSubmission {
  const FoodSubmission({
    required this.food,
    required this.price,
    this.isFake = false,
    this.priceMin = 0,
    this.priceMax = 0,
    this.imageUrl,
    this.imageId,
    this.confidence = 0,
    this.isLocalFood = false,
    this.variant = '',
    this.dietaryRestrictions = const <String>[],
  });

  final LocalFood food;
  final double price;

  /// Test/QA marker - `true` for "fake food" (see `LandmarkItem.isFake`).
  final bool isFake;

  /// Suggested MYR price range for [food] from Gemini - carried onto the
  /// persisted [LandmarkItem]. `0` means unknown.
  final double priceMin;
  final double priceMax;

  /// Where this food's photo lives after upload, carried onto the persisted
  /// [LandmarkItem] (`landmark_item.image_url` / `image_id`). Null when the
  /// food has no photo (e.g. a name-typed food) - the repository writes null.
  final String? imageUrl;
  final String? imageId;

  /// Gemini's confidence (0..1) in this dish's NAME, carried from the
  /// recognition screen so the catalogue-growth gate can demand a HIGH bar
  /// before writing a new `local_food` row. `0` when unknown (never
  /// catalogue-insert eligible).
  final double confidence;

  /// Whether Gemini judged this dish Malaysian local food. Only true dishes
  /// may be added to the shared `local_food` catalogue.
  final bool isLocalFood;

  /// The name the dish was actually recognised/typed as when it EXTENDS the
  /// dictionary [food]'s name into an unlisted variant (`Cendol Jagung`
  /// linking to the curated `Cendol`) - written to `landmark_item.variant`.
  /// Empty when the name IS the dish (its name/synonym/same words
  /// reordered).
  final String variant;

  /// Dietary restrictions that apply to this dish (canonical
  /// `dietary_restriction.restriction_name` strings), from Gemini's full
  /// analysis. Written to the `food_dietary_restriction` ASSOCIATION table
  /// when the dish becomes a new catalogue row - deliberately carried here,
  /// not on `LocalFood`, because dietary is an association, not a `local_food`
  /// column.
  final List<String> dietaryRestrictions;
}
