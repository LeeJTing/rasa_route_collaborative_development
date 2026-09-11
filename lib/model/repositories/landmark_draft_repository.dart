import 'dart:developer' as developer;

import '../../domain_model/landmark_draft.dart';
import '../../domain_model/local_food.dart';
import '../../domain_model/opening_hour.dart';
import '../../domain_model/tourist_location.dart';
import '../../shared_client/api_manager/api_manager.dart';
import '../data_models/landmark_draft_data_model.dart';

/// Saved (incomplete) Add-New-Landmark forms - `public.landmark_draft`.
///
/// A repository is the only layer that talks to the shared clients. It asks
/// `APIManager` for raw rows, hands them to a **data model** (`fromJson`),
/// then converts that data model into a **domain model** for everything
/// above.
///
/// Drafts are written through the anon key (same as every tourist-facing
/// table) and are scoped by `tourist_id`. Each draft lives for 24 hours from
/// its last save - the logic layer stamps `expiresAt`; this repository just
/// persists it. Deleting a draft also deletes its uploaded photos from the
/// `landmark-images` bucket (best-effort - the row is removed even if
/// storage cleanup fails).
class LandmarkDraftRepository {
  LandmarkDraftRepository();

  final APIManager api = APIManager();

  /// Inserts ([draft].id == 0) or updates a draft for [touristId], returns
  /// the draft id.
  Future<int> save({
    required String touristId,
    required LandmarkDraft draft,
  }) async {
    final LandmarkDraftDataModel model = _toDataModel(touristId, draft);
    final Map<String, dynamic> payload =
        model.toJson()['payload'] as Map<String, dynamic>;
    final Map<String, dynamic> values = <String, dynamic>{
      'tourist_id': model.touristId,
      'restaurant_name': model.restaurantName,
      'thumbnail_url': model.thumbnailUrl,
      'payload': payload,
      'expires_at': model.expiresAt.toUtc().toIso8601String(),
      'updated_at': (model.updatedAt ?? DateTime.now())
          .toUtc()
          .toIso8601String(),
    };

    if (draft.id == 0) {
      final Map<String, dynamic>? row = await api.insertRowReturning(
        APIManager.tableLandmarkDraft,
        values,
      );
      return (row?['draft_id'] as num?)?.toInt() ?? 0;
    }

    await api.updateRow(
      APIManager.tableLandmarkDraft,
      values,
      eq: <String, Object?>{'draft_id': draft.id},
    );
    return draft.id;
  }

  /// The tourist's saved drafts, newest first.
  Future<List<LandmarkDraft>> draftsByTourist(String touristId) async {
    final List<Map<String, dynamic>> rows = await api.selectAll(
      APIManager.tableLandmarkDraft,
      eq: <String, Object?>{'tourist_id': touristId},
      orderBy: 'updated_at',
      ascending: false,
    );
    return <LandmarkDraft>[
      for (final Map<String, dynamic> row in rows)
        _toDomain(LandmarkDraftDataModel.fromJson(row)),
    ];
  }

  /// Removes one draft AND its uploaded photos. The row is always deleted;
  /// storage cleanup is best-effort (an object that is already gone must not
  /// keep the draft alive).
  Future<void> deleteDraft(LandmarkDraft draft) async {
    await _deletePhotos(draft);
    await api.deleteRows(
      APIManager.tableLandmarkDraft,
      eq: <String, Object?>{'draft_id': draft.id},
    );
  }

  /// Deletes every photo stored for [draft] (the landmark's own photo and
  /// each food's photo) from the `landmark-images` bucket. Best-effort.
  Future<void> _deletePhotos(LandmarkDraft draft) async {
    final List<String> objectIds = <String>[
      if (draft.landmarkPhoto != null) draft.landmarkPhoto!.id,
      for (final LandmarkDraftFood food in draft.foods)
        if (food.photo != null) food.photo!.id,
    ];
    if (objectIds.isEmpty) return;
    try {
      await api.deleteLandmarkImages(objectIds);
    } catch (error, stackTrace) {
      developer.log(
        'Could not delete landmark-draft photos: $error',
        name: 'LandmarkDraftRepository',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Removes one draft ROW without touching its photos - used after a
  /// SUCCESSFUL submission, because the landmark now stores those same
  /// photo objects and deleting them would blank the submitted landmark's
  /// images.
  Future<void> deleteDraftRow(int draftId) => api.deleteRows(
    APIManager.tableLandmarkDraft,
    eq: <String, Object?>{'draft_id': draftId},
  );

  /// Deletes ONE uploaded photo by its storage object name - used when a
  /// draft's photo is replaced by a fresh capture, so the old object does
  /// not linger. Best-effort.
  Future<void> deletePhoto(String objectId) async {
    if (objectId.trim().isEmpty) return;
    try {
      await api.deleteLandmarkImages(<String>[objectId]);
    } catch (error, stackTrace) {
      developer.log(
        'Could not delete landmark-draft photo: $error',
        name: 'LandmarkDraftRepository',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Conversion (data model <-> domain model)
  // ---------------------------------------------------------------------------

  LandmarkDraft _toDomain(LandmarkDraftDataModel model) {
    final Map<Weekday, List<OpeningHour>> operatingHours =
        <Weekday, List<OpeningHour>>{};
    for (final LandmarkDraftHourDataModel hour in model.operatingHours) {
      final Weekday day = _weekdayFromName(hour.day);
      operatingHours
          .putIfAbsent(day, () => <OpeningHour>[])
          .add(
            OpeningHour(
              id: 0,
              day: day,
              status: _dayStatusFromName(hour.status),
              opensAt: hour.opensAt,
              closesAt: hour.closesAt,
            ),
          );
    }

    return LandmarkDraft(
      id: model.draftId,
      restaurantName: model.restaurantName,
      phone: model.phone,
      website: model.website,
      address: model.address,
      category: model.category,
      restaurantConfirmed: model.restaurantConfirmed,
      baseLocation: _location(model.baseLatitude, model.baseLongitude),
      adjustedLocation: _location(
        model.adjustedLatitude,
        model.adjustedLongitude,
      ),
      landmarkPhoto: _photoToDomain(model.landmarkPhoto),
      foods: <LandmarkDraftFood>[
        for (final LandmarkDraftFoodDataModel food in model.foods)
          LandmarkDraftFood(
            food: _foodToDomain(food.food),
            price: food.price,
            priceMin: food.priceMin,
            priceMax: food.priceMax,
            confidence: food.confidence,
            dietaryRestrictions: food.dietaryRestrictions,
            variant: food.variant,
            captureLocation: _location(
              food.captureLatitude,
              food.captureLongitude,
            ),
            photo: _photoToDomain(food.photo),
          ),
      ],
      operatingHours: operatingHours,
      expiresAt: model.expiresAt,
      updatedAt: model.updatedAt ?? model.createdAt ?? DateTime.now(),
    );
  }

  LandmarkDraftDataModel _toDataModel(String touristId, LandmarkDraft draft) {
    final LandmarkDraftPhoto? thumbnail =
        draft.primaryFood?.photo ?? draft.landmarkPhoto;
    return LandmarkDraftDataModel(
      draftId: draft.id,
      touristId: touristId,
      restaurantName: draft.restaurantName,
      thumbnailUrl: thumbnail?.url,
      phone: draft.phone,
      website: draft.website,
      address: draft.address,
      category: draft.category,
      restaurantConfirmed: draft.restaurantConfirmed,
      baseLatitude: draft.baseLocation.isKnown
          ? draft.baseLocation.latitude
          : null,
      baseLongitude: draft.baseLocation.isKnown
          ? draft.baseLocation.longitude
          : null,
      adjustedLatitude: draft.adjustedLocation.isKnown
          ? draft.adjustedLocation.latitude
          : null,
      adjustedLongitude: draft.adjustedLocation.isKnown
          ? draft.adjustedLocation.longitude
          : null,
      landmarkPhoto: _photoToDataModel(draft.landmarkPhoto),
      foods: <LandmarkDraftFoodDataModel>[
        for (final LandmarkDraftFood food in draft.foods)
          LandmarkDraftFoodDataModel(
            food: _foodToDataModel(food.food),
            price: food.price,
            priceMin: food.priceMin,
            priceMax: food.priceMax,
            confidence: food.confidence,
            dietaryRestrictions: food.dietaryRestrictions,
            variant: food.variant,
            captureLatitude: food.captureLocation.isKnown
                ? food.captureLocation.latitude
                : null,
            captureLongitude: food.captureLocation.isKnown
                ? food.captureLocation.longitude
                : null,
            photo: _photoToDataModel(food.photo),
          ),
      ],
      operatingHours: <LandmarkDraftHourDataModel>[
        for (final MapEntry<Weekday, List<OpeningHour>> entry
            in draft.operatingHours.entries)
          for (final OpeningHour hour in entry.value)
            LandmarkDraftHourDataModel(
              day: hour.day.name,
              status: hour.status.name,
              opensAt: hour.opensAt,
              closesAt: hour.closesAt,
            ),
      ],
      expiresAt: draft.expiresAt,
      updatedAt: draft.updatedAt,
    );
  }

  static TouristLocation _location(double? latitude, double? longitude) {
    if (latitude == null || longitude == null) return TouristLocation.unknown;
    return TouristLocation(latitude: latitude, longitude: longitude);
  }

  static LandmarkDraftPhoto? _photoToDomain(
    LandmarkDraftPhotoDataModel? photo,
  ) {
    if (photo == null || photo.id.isEmpty || photo.url.isEmpty) return null;
    return LandmarkDraftPhoto(
      id: photo.id,
      url: photo.url,
      type: photo.type,
      captureLocation: _location(photo.captureLatitude, photo.captureLongitude),
    );
  }

  static LandmarkDraftPhotoDataModel? _photoToDataModel(
    LandmarkDraftPhoto? photo,
  ) {
    if (photo == null) return null;
    return LandmarkDraftPhotoDataModel(
      id: photo.id,
      url: photo.url,
      type: photo.type,
      captureLatitude: photo.captureLocation.isKnown
          ? photo.captureLocation.latitude
          : null,
      captureLongitude: photo.captureLocation.isKnown
          ? photo.captureLocation.longitude
          : null,
    );
  }

  static LocalFood _foodToDomain(LandmarkDraftDishDataModel food) => LocalFood(
    id: food.id,
    name: food.name,
    description: food.description,
    origin: food.origin,
    culturalBackground: food.culturalBackground,
    ingredients: food.ingredients,
    category: food.category,
    cookingStyle: food.cookingStyle,
    mealType: food.mealType,
    foodType: food.foodType,
    tastes: food.tastes,
    mainTaste: food.mainTaste,
    synonyms: food.synonyms,
  );

  static LandmarkDraftDishDataModel _foodToDataModel(LocalFood food) =>
      LandmarkDraftDishDataModel(
        id: food.id,
        name: food.name,
        description: food.description,
        origin: food.origin,
        culturalBackground: food.culturalBackground,
        ingredients: food.ingredients,
        category: food.category,
        cookingStyle: food.cookingStyle,
        mealType: food.mealType,
        foodType: food.foodType,
        tastes: food.tastes,
        mainTaste: food.mainTaste,
        synonyms: food.synonyms,
      );

  static Weekday _weekdayFromName(String name) {
    for (final Weekday day in Weekday.values) {
      if (day.name == name) return day;
    }
    return Weekday.monday;
  }

  static DayStatus _dayStatusFromName(String name) {
    for (final DayStatus status in DayStatus.values) {
      if (status.name == name) return status;
    }
    return DayStatus.unknown;
  }
}
