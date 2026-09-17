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
    this.status,
    this.closedUntil,
    this.items = const <RestaurantItem>[],
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
  final String? status;

  /// When a temporary closure (`status='frozen'`) is due to end - read-time
  /// availability treats a `frozen` place with `closed_until` in the past as
  /// available again (see `PlaceClosureRules`). Null when never temporarily
  /// closed, or already reactivated.
  final DateTime? closedUntil;

  final List<RestaurantItem> items;

  Restaurant copyWith({
    int? id,
    String? name,
    String? category,
    String? address,
    double? rating,
    double? latitude,
    double? longitude,
    String? phone,
    String? website,
    String? imageUrl,
    List<OpeningHour>? openingHours,
    double? distanceMetres,
    int? reviewCount,
    String? status,
    DateTime? closedUntil,
    List<RestaurantItem>? items,
  }) => Restaurant(
    id: id ?? this.id,
    name: name ?? this.name,
    category: category ?? this.category,
    address: address ?? this.address,
    rating: rating ?? this.rating,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    phone: phone ?? this.phone,
    website: website ?? this.website,
    imageUrl: imageUrl ?? this.imageUrl,
    openingHours: openingHours ?? this.openingHours,
    distanceMetres: distanceMetres ?? this.distanceMetres,
    reviewCount: reviewCount ?? this.reviewCount,
    status: status ?? this.status,
    closedUntil: closedUntil ?? this.closedUntil,
    items: items ?? this.items,
  );
}
