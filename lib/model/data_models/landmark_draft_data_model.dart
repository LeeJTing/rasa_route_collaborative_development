import '../../core/json_model.dart';

/// Wire shape of `public.landmark_draft` - one saved (incomplete)
/// Add-New-Landmark form.
///
/// The row is deliberately thin (`tourist_id`, `restaurant_name`,
/// `thumbnail_url`, `expires_at` for the list UI); the form snapshot itself
/// lives in the `payload` jsonb column, which this model parses into typed
/// sub-models so the repository never touches raw JSON keys:
///   * [LandmarkDraftFoodDataModel] - one food + its price/photo/location;
///   * [LandmarkDraftPhotoDataModel] - a storage object name + public URL;
///   * [LandmarkDraftHourDataModel] - one opening-hours row.
///
/// Only the fields a resumed form needs are stored on a food - the curated
/// detail fields and the recognition-derived values used when the food
/// becomes a catalogue row. Transient recognition data (`LocalFood.aliases`,
/// gallery images, favourite state) is intentionally absent.
class LandmarkDraftDataModel implements JsonModel {
  const LandmarkDraftDataModel({
    required this.draftId,
    required this.touristId,
    this.restaurantName = '',
    this.thumbnailUrl,
    this.phone = '',
    this.website = '',
    this.address = '',
    this.category = '',
    this.restaurantConfirmed = false,
    this.baseLatitude,
    this.baseLongitude,
    this.adjustedLatitude,
    this.adjustedLongitude,
    this.landmarkPhoto,
    this.foods = const <LandmarkDraftFoodDataModel>[],
    this.operatingHours = const <LandmarkDraftHourDataModel>[],
    required this.expiresAt,
    this.createdAt,
    this.updatedAt,
  });

  /// `landmark_draft.draft_id` (bigint, identity PK). `0` for a row not yet
  /// saved.
  final int draftId;

  /// `landmark_draft.tourist_id` - whose draft this is.
  final String touristId;

  /// Denormalised restaurant name for the draft list.
  final String restaurantName;

  /// Denormalised thumbnail (primary food photo, else signboard/stall photo).
  final String? thumbnailUrl;

  final String phone;
  final String website;
  final String address;

  /// The primary food's category (`submitted_landmark.category` on submit).
  final String category;

  /// Whether the tourist confirmed the restaurant details ("Confirm" under
  /// the Restaurant Name) before this save.
  final bool restaurantConfirmed;

  /// Where the FIRST food was captured - `null` when no fix was available.
  final double? baseLatitude;
  final double? baseLongitude;

  /// A hand-moved pin, `null` when the tourist left it at the captured fix.
  final double? adjustedLatitude;
  final double? adjustedLongitude;

  /// The landmark's own signboard/stall photo, `null` when not captured yet.
  final LandmarkDraftPhotoDataModel? landmarkPhoto;

  /// The form's foods, primary first.
  final List<LandmarkDraftFoodDataModel> foods;

  /// The form's opening-hours rows, flat (one row per day/range).
  final List<LandmarkDraftHourDataModel> operatingHours;

  /// `landmark_draft.expires_at` - 24 hours after the last save.
  final DateTime expiresAt;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory LandmarkDraftDataModel.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> payload = JsonReader.asMap(json['payload']);
    return LandmarkDraftDataModel(
      draftId: JsonReader.asInt(json['draft_id']),
      touristId: JsonReader.asString(json['tourist_id']),
      restaurantName: JsonReader.asString(payload['restaurant_name']),
      thumbnailUrl: JsonReader.asStringOrNull(json['thumbnail_url']),
      phone: JsonReader.asString(payload['phone']),
      website: JsonReader.asString(payload['website']),
      address: JsonReader.asString(payload['address']),
      category: JsonReader.asString(payload['category']),
      restaurantConfirmed: JsonReader.asBool(payload['restaurant_confirmed']),
      baseLatitude: JsonReader.asDoubleOrNull(payload['base_latitude']),
      baseLongitude: JsonReader.asDoubleOrNull(payload['base_longitude']),
      adjustedLatitude: JsonReader.asDoubleOrNull(payload['adjusted_latitude']),
      adjustedLongitude: JsonReader.asDoubleOrNull(
        payload['adjusted_longitude'],
      ),
      landmarkPhoto: JsonReader.asMapOrNull(payload['landmark_photo']) == null
          ? null
          : LandmarkDraftPhotoDataModel.fromJson(
              JsonReader.asMap(payload['landmark_photo']),
            ),
      foods: JsonReader.asModelList(
        payload['foods'],
        LandmarkDraftFoodDataModel.fromJson,
      ),
      operatingHours: JsonReader.asModelList(
        payload['operating_hours'],
        LandmarkDraftHourDataModel.fromJson,
      ),
      expiresAt: JsonReader.asDate(json['expires_at']),
      createdAt: JsonReader.asDateOrNull(json['created_at']),
      updatedAt: JsonReader.asDateOrNull(json['updated_at']),
    );
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'draft_id': draftId,
    'tourist_id': touristId,
    'restaurant_name': restaurantName,
    'thumbnail_url': thumbnailUrl,
    'expires_at': expiresAt.toIso8601String(),
    'created_at': createdAt?.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
    'payload': <String, dynamic>{
      'restaurant_name': restaurantName,
      'phone': phone,
      'website': website,
      'address': address,
      'category': category,
      'restaurant_confirmed': restaurantConfirmed,
      'base_latitude': baseLatitude,
      'base_longitude': baseLongitude,
      'adjusted_latitude': adjustedLatitude,
      'adjusted_longitude': adjustedLongitude,
      'landmark_photo': landmarkPhoto?.toJson(),
      'foods': <Map<String, dynamic>>[
        for (final LandmarkDraftFoodDataModel food in foods) food.toJson(),
      ],
      'operating_hours': <Map<String, dynamic>>[
        for (final LandmarkDraftHourDataModel hour in operatingHours)
          hour.toJson(),
      ],
    },
  };
}

/// One food saved in a draft's payload - the dish plus everything the form
/// was holding for it.
class LandmarkDraftFoodDataModel implements JsonModel {
  const LandmarkDraftFoodDataModel({
    required this.food,
    this.price,
    this.priceMin = 0,
    this.priceMax = 0,
    this.confidence = 0,
    this.dietaryRestrictions = const <String>[],
    this.variant = '',
    this.captureLatitude,
    this.captureLongitude,
    this.photo,
  });

  /// The dish itself (`payload.foods[].food`).
  final LandmarkDraftDishDataModel food;

  /// The price the tourist entered, null when not entered yet.
  final double? price;

  /// Gemini's suggested range. `0` means unknown.
  final double priceMin;
  final double priceMax;

  /// Gemini's confidence in the dish name (primary food only).
  final double confidence;

  /// Canonical dietary-restriction names carried for catalogue growth.
  final List<String> dietaryRestrictions;

  /// The VARIANT name this food was seen/typed as when it EXTENDS the
  /// dictionary dish into an unlisted variant (`Cendol Jagung` -> `Cendol`) -
  /// restored onto the form and written to `landmark_item.variant`. Empty
  /// when the name IS the dish.
  final String variant;

  /// Where this food was captured.
  final double? captureLatitude;
  final double? captureLongitude;

  /// This food's own photo, when one was captured.
  final LandmarkDraftPhotoDataModel? photo;

  factory LandmarkDraftFoodDataModel.fromJson(
    Map<String, dynamic> json,
  ) => LandmarkDraftFoodDataModel(
    food: LandmarkDraftDishDataModel.fromJson(JsonReader.asMap(json['food'])),
    price: JsonReader.asDoubleOrNull(json['price']),
    priceMin: JsonReader.asDouble(json['price_min']),
    priceMax: JsonReader.asDouble(json['price_max']),
    confidence: JsonReader.asDouble(json['confidence']),
    dietaryRestrictions: JsonReader.asStringList(json['dietary_restrictions']),
    variant: JsonReader.asString(json['variant']),
    captureLatitude: JsonReader.asDoubleOrNull(json['capture_latitude']),
    captureLongitude: JsonReader.asDoubleOrNull(json['capture_longitude']),
    photo: JsonReader.asMapOrNull(json['photo']) == null
        ? null
        : LandmarkDraftPhotoDataModel.fromJson(JsonReader.asMap(json['photo'])),
  );

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'food': food.toJson(),
    'price': price,
    'price_min': priceMin,
    'price_max': priceMax,
    'confidence': confidence,
    'dietary_restrictions': dietaryRestrictions,
    'variant': variant,
    'capture_latitude': captureLatitude,
    'capture_longitude': captureLongitude,
    'photo': photo?.toJson(),
  };
}

/// A photo stored in a draft - the storage object name (`image_id`) and the
/// public URL, plus the capture kind (`signboard` / `stall`) and the spot the
/// photo was taken for the landmark's own photo.
class LandmarkDraftPhotoDataModel implements JsonModel {
  const LandmarkDraftPhotoDataModel({
    required this.id,
    required this.url,
    this.type,
    this.captureLatitude,
    this.captureLongitude,
  });

  final String id;
  final String url;
  final String? type;

  /// Where the photo was taken - null for a food photo (its spot rides on
  /// the food entry) or when no fix was available.
  final double? captureLatitude;
  final double? captureLongitude;

  factory LandmarkDraftPhotoDataModel.fromJson(Map<String, dynamic> json) =>
      LandmarkDraftPhotoDataModel(
        id: JsonReader.asString(json['id']),
        url: JsonReader.asString(json['url']),
        type: JsonReader.asStringOrNull(json['type']),
        captureLatitude: JsonReader.asDoubleOrNull(json['capture_latitude']),
        captureLongitude: JsonReader.asDoubleOrNull(json['capture_longitude']),
      );

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'url': url,
    'type': type,
    'capture_latitude': captureLatitude,
    'capture_longitude': captureLongitude,
  };
}

/// One opening-hours row in a draft's payload - `(day, status, opensAt,
/// closesAt)`, matching `OpeningHour` and the real table's per-row shape.
class LandmarkDraftHourDataModel implements JsonModel {
  const LandmarkDraftHourDataModel({
    required this.day,
    required this.status,
    this.opensAt,
    this.closesAt,
  });

  /// `monday`..`sunday` (see `Weekday`).
  final String day;

  /// `open` | `unknown` | `closed` (see `DayStatus`).
  final String status;

  /// Minutes since midnight (0-1440), null for closed/unknown rows.
  final int? opensAt;
  final int? closesAt;

  factory LandmarkDraftHourDataModel.fromJson(Map<String, dynamic> json) =>
      LandmarkDraftHourDataModel(
        day: JsonReader.asString(json['day']),
        status: JsonReader.asString(json['status']),
        opensAt: JsonReader.asIntOrNull(json['opens_at']),
        closesAt: JsonReader.asIntOrNull(json['closes_at']),
      );

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'day': day,
    'status': status,
    'opens_at': opensAt,
    'closes_at': closesAt,
  };
}

/// The dish stored inside `payload.foods[].food` - the subset of
/// `local_food` a resumed form needs (detail fields kept for the
/// submitted `landmark_item` and for catalogue growth when the dish gets a
/// new `local_food` row). Mirrors the columns `RecognitionRepository`
/// reads, minus the transient recognition-only fields. Distinct from the
/// table-shaped `LocalFoodDataModel` in `local_food_data_model.dart`
/// (which has no taste data and is keyed by `local_food_id`).
class LandmarkDraftDishDataModel implements JsonModel {
  const LandmarkDraftDishDataModel({
    required this.id,
    required this.name,
    this.description = '',
    this.origin = '',
    this.culturalBackground = '',
    this.ingredients = '',
    this.category = '',
    this.cookingStyle = '',
    this.mealType = '',
    this.foodType = '',
    this.tastes = const <String>[],
    this.mainTaste = '',
    this.synonyms = const <String>[],
  });

  final int id;
  final String name;
  final String description;
  final String origin;
  final String culturalBackground;
  final String ingredients;
  final String category;
  final String cookingStyle;
  final String mealType;
  final String foodType;
  final List<String> tastes;
  final String mainTaste;
  final List<String> synonyms;

  factory LandmarkDraftDishDataModel.fromJson(Map<String, dynamic> json) =>
      LandmarkDraftDishDataModel(
        id: JsonReader.asInt(json['id']),
        name: JsonReader.asString(json['name']),
        description: JsonReader.asString(json['description']),
        origin: JsonReader.asString(json['origin']),
        culturalBackground: JsonReader.asString(json['cultural_background']),
        ingredients: JsonReader.asString(json['ingredients']),
        category: JsonReader.asString(json['category']),
        cookingStyle: JsonReader.asString(json['cooking_style']),
        mealType: JsonReader.asString(json['meal_type']),
        foodType: JsonReader.asString(json['food_type']),
        tastes: JsonReader.asStringList(json['tastes']),
        mainTaste: JsonReader.asString(json['main_taste']),
        synonyms: JsonReader.asStringList(json['synonyms']),
      );

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'description': description,
    'origin': origin,
    'cultural_background': culturalBackground,
    'ingredients': ingredients,
    'category': category,
    'cooking_style': cookingStyle,
    'meal_type': mealType,
    'food_type': foodType,
    'tastes': tastes,
    'main_taste': mainTaste,
    'synonyms': synonyms,
  };
}
