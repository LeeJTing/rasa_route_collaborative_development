import '../../core/json_model.dart';

/// Wire shape of `public.restaurant`.
///
/// `reported_times` and `status` shown in an earlier ERD are not present in the
/// current database schema.
class RestaurantDataModel implements JsonModel {
  const RestaurantDataModel({
    required this.restaurantId,
    required this.restaurantName,
    this.category,
    this.address,
    this.rating,
    this.longitude,
    this.latitude,
    this.phone,
    this.website,
    this.openingHours,
    this.restaurantImageId,
    this.restaurantImageUrl,
  });

  /// `restaurant.restaurant_id` (bigint identity, PK).
  final int restaurantId;

  /// `restaurant.restaurant_name` (text, not null).
  final String restaurantName;

  final String? category;
  final String? address;

  /// `restaurant.rating` (numeric, 0..5). Arrives as `String` on some drivers.
  final double? rating;

  final double? longitude;
  final double? latitude;
  final String? phone;
  final String? website;

  /// Free-text duplicate of the `opening_hours` table - prefer the table.
  final String? openingHours;

  final String? restaurantImageId;
  final String? restaurantImageUrl;

  factory RestaurantDataModel.fromJson(Map<String, dynamic> json) {
    return RestaurantDataModel(
      restaurantId: JsonReader.asInt(json['restaurant_id']),
      restaurantName: JsonReader.asString(json['restaurant_name']),
      category: JsonReader.asStringOrNull(json['category']),
      address: JsonReader.asStringOrNull(json['address']),
      rating: JsonReader.asDoubleOrNull(json['rating']),
      longitude: JsonReader.asDoubleOrNull(json['longitude']),
      latitude: JsonReader.asDoubleOrNull(json['latitude']),
      phone: JsonReader.asStringOrNull(json['phone']),
      website: JsonReader.asStringOrNull(json['website']),
      openingHours: JsonReader.asStringOrNull(json['opening_hours']),
      restaurantImageId: JsonReader.asStringOrNull(json['restaurant_image_id']),
      restaurantImageUrl: JsonReader.asStringOrNull(
        json['restaurant_image_url'],
      ),
    );
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'restaurant_id': restaurantId,
    'restaurant_name': restaurantName,
    'category': category,
    'address': address,
    'rating': rating,
    'longitude': longitude,
    'latitude': latitude,
    'phone': phone,
    'website': website,
    'opening_hours': openingHours,
    'restaurant_image_id': restaurantImageId,
    'restaurant_image_url': restaurantImageUrl,
  };
}
