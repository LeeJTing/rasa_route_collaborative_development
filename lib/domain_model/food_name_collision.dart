import 'local_food.dart';

/// Two catalogue foods that share one ordering name but describe different
/// dishes in different Malaysian regions.
class FoodNameCollision {
  const FoodNameCollision({
    required this.sharedName,
    required this.alternateFood,
  });

  final String sharedName;
  final LocalFood alternateFood;
}
