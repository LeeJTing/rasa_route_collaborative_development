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
  final List<LandmarkItem> items;
  final List<OpeningHour> openingHours;
}

/// Moderation state of a submission.
enum LandmarkStatus { pending, approved, rejected }

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
    required this.dish,
    required this.variant,
    required this.foodCategory,
    required this.description,
    required this.origin,
    required this.culturalBackground,
    this.imageUrl,
    this.imageId,
    this.price,
    required this.seasonal,
    required this.cookingStyle,
    required this.mealType,
    this.isFake = false,
  });

  final int id;
  final int landmarkId;
  final String touristId;
  final String dish;
  final String variant;
  final String foodCategory;
  final String description;
  final String origin;
  final String culturalBackground;

  /// The food's own photo (as captured on `FoodRecognitionView`), once
  /// actually uploaded somewhere - null until a real image-storage
  /// repository exists (see `AddLandmarkViewModel._toLandmarkItem`'s note).
  ///
  /// `image_id` in `landmark_item` is `text` (a storage object id) - not an
  /// integer, matching the real Supabase column.
  final String? imageUrl;
  final String? imageId;
  final double? price;
  final String seasonal;
  final String cookingStyle;
  final String mealType;

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
  });

  final LocalFood food;
  final double price;

  /// Test/QA marker - `true` for "fake food" (see `LandmarkItem.isFake`).
  final bool isFake;
}
