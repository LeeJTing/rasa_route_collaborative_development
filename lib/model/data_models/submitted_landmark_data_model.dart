import '../../core/json_model.dart';

/// Wire shape of `public.submitted_landmark`.
///
/// NOTE: the ERD calls this entity `Landmark` and its counter
/// `reported_times`; the database calls them `submitted_landmark` /
/// `reported_count`. This model follows the **database**.
class SubmittedLandmarkDataModel implements JsonModel {
  const SubmittedLandmarkDataModel({
    required this.landmarkId,
    this.landmarkName,
    this.longitude,
    this.latitude,
    this.category,
    this.reportedCount = 0,
    this.status,
    this.imageUrl,
    this.imageId,
    this.imageCategory,
  });

  /// `submitted_landmark.landmark_id` (bigint, PK - no identity, supply it).
  final int landmarkId;

  final String? landmarkName;
  final double? longitude;
  final double? latitude;
  final String? category;

  /// `submitted_landmark.reported_count` (smallint, default 0).
  final int reportedCount;

  /// Free text: `available` | `frozen` (see `LandmarkStatus`). A new
  /// submission is always `available` with `reported_count` 0.
  final String? status;

  /// The landmark's own signboard/stall photo - `submitted_landmark.image_url`
  /// / `image_id` / `image_category` (all text, in the `landmark-images`
  /// storage bucket). `imageCategory` is `'signboard'` or `'stall'`.
  final String? imageUrl;
  final String? imageId;
  final String? imageCategory;

  factory SubmittedLandmarkDataModel.fromJson(Map<String, dynamic> json) {
    return SubmittedLandmarkDataModel(
      landmarkId: JsonReader.asInt(json['landmark_id']),
      landmarkName: JsonReader.asStringOrNull(json['landmark_name']),
      longitude: JsonReader.asDoubleOrNull(json['longitude']),
      latitude: JsonReader.asDoubleOrNull(json['latitude']),
      category: JsonReader.asStringOrNull(json['category']),
      reportedCount: JsonReader.asInt(json['reported_count']),
      status: JsonReader.asStringOrNull(json['status']),
      imageUrl: JsonReader.asStringOrNull(json['image_url']),
      imageId: JsonReader.asStringOrNull(json['image_id']),
      imageCategory: JsonReader.asStringOrNull(json['image_category']),
    );
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'landmark_id': landmarkId,
    'landmark_name': landmarkName,
    'longitude': longitude,
    'latitude': latitude,
    'category': category,
    'reported_count': reportedCount,
    'status': status,
    'image_url': imageUrl,
    'image_id': imageId,
    'image_category': imageCategory,
  };
}
