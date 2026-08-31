import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/model/repositories/restaurant_repository.dart';

void main() {
  group('restaurant item catalogue-image fallback', () {
    final RestaurantRepository repository = RestaurantRepository();

    test('allows a linked image when the food name matches', () {
      expect(
        repository.catalogueImageMatchesItem(
          restaurantItemName: 'Signature Chilli Pan Mee (Dry)',
          localFoodName: 'Chili Pan Mee',
        ),
        isTrue,
      );
    });

    test('rejects an unrelated linked food image', () {
      expect(
        repository.catalogueImageMatchesItem(
          restaurantItemName: 'Chilli Pan Mee (Dry)',
          localFoodName: 'Curry Laksa',
        ),
        isFalse,
      );
    });
  });
}
