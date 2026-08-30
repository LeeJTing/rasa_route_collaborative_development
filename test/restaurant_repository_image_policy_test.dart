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

    test('accepts common Char Kway Teow spelling variants', () {
      expect(
        repository.catalogueImageMatchesItem(
          restaurantItemName: 'Signature Penang Char Kuey Teow',
          localFoodName: 'Char Kway Teow',
        ),
        isTrue,
      );
      expect(
        repository.catalogueImageMatchesItem(
          restaurantItemName: 'Char Koay Teow Udang',
          localFoodName: 'Char Kway Teow',
        ),
        isTrue,
      );
    });

    test('keeps generic Kuey Teow dishes on the neutral fallback', () {
      expect(
        repository.catalogueImageMatchesItem(
          restaurantItemName: 'Kuey Teow Soup',
          localFoodName: 'Char Kway Teow',
        ),
        isFalse,
      );
    });
  });
}
