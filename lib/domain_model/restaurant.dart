import 'opening_hour.dart';
import 'restaurant_item.dart';

/// A restaurant that serves local food.
/// [distanceMetres] is filled in by the logic layer against the current fix.
///
/// Domain models are plain data types. They carry no JSON - serialisation is
/// the data model's job in `lib/model/data_models/`, and the repository is what
/// converts a data model into one of these. They travel upward unchanged from
/// repository to logic to ViewModel to View.
class Restaurant {
  const Restaurant({
    required this.id,
    required this.name,
    required this.category,
    required this.address,
    this.rating,
    this.latitude,
    this.longitude,
    required this.phone,
    required this.website,
    this.imageUrl,
    required this.openingHours,
    this.distanceMetres,
    this.reviewCount,
    this.items = const <RestaurantItem>[],
    this.isHalal,
  });

  final int id;
  final String name;
  final String category;
  final String address;
  final double? rating;
  final double? latitude;
  final double? longitude;
  final String phone;
  final String website;
  final String? imageUrl;
  final List<OpeningHour> openingHours;
  final double? distanceMetres;
  final int? reviewCount;
  final List<RestaurantItem> items;

  /// Null for live rows until the planned `restaurant.is_halal` migration.
  final bool? isHalal;

  String get distanceLabel {
    final double? metres = distanceMetres;
    if (metres == null) return 'Distance unavailable';
    if (metres < 1000) return '${metres.round()} m';
    return '${(metres / 1000).toStringAsFixed(1)} km';
  }

  Restaurant copyWith({double? distanceMetres, List<RestaurantItem>? items}) =>
      Restaurant(
        id: id,
        name: name,
        category: category,
        address: address,
        rating: rating,
        latitude: latitude,
        longitude: longitude,
        phone: phone,
        website: website,
        imageUrl: imageUrl,
        openingHours: openingHours,
        distanceMetres: distanceMetres ?? this.distanceMetres,
        reviewCount: reviewCount,
        items: items ?? this.items,
        isHalal: isHalal,
      );
}
