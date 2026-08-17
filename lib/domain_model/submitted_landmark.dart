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
    this.price,
    required this.seasonal,
    required this.cookingStyle,
    required this.mealType,
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
  final String? imageUrl;
  final double? price;
  final String seasonal;
  final String cookingStyle;
  final String mealType;
}
