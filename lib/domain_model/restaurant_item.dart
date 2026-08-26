/// One dish on one restaurant's menu.
///
/// Domain models are plain data types. They carry no JSON - serialisation is
/// the data model's job in `lib/model/data_models/`, and the repository is what
/// converts a data model into one of these. They travel upward unchanged from
/// repository to logic to ViewModel to View.
class RestaurantItem {
  const RestaurantItem({
    required this.id,
    required this.restaurantId,
    required this.localFoodId,
    required this.foodName,
    this.ingredients,
    this.imageUrl,
    this.price,
    required this.currency,
    required this.foodCategory,
  });

  final int id;
  final int restaurantId;
  final int localFoodId;
  final String foodName;
  final String? ingredients;
  final String? imageUrl;
  final double? price;
  final String currency;
  final String foodCategory;
}
