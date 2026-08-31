import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/restaurant_item.dart';
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

    test('deduplicates equal menu names and prices using the richer row', () {
      const RestaurantItem withoutPhoto = RestaurantItem(
        id: 1,
        restaurantId: 9,
        localFoodId: 12,
        foodName: 'Char Kway Teow',
        price: 8.9,
        currency: 'RM',
        foodCategory: 'Chinese',
      );
      const RestaurantItem withPhoto = RestaurantItem(
        id: 2,
        restaurantId: 9,
        localFoodId: 12,
        foodName: ' char  kway-teow ',
        ingredients: 'Noodles and prawns',
        imageUrl: 'https://example.test/char-kway-teow.jpg',
        price: 8.9,
        currency: 'RM',
        foodCategory: 'Chinese',
      );

      final List<RestaurantItem> result = repository.deduplicateRestaurantItems(
        <RestaurantItem>[withoutPhoto, withPhoto],
      );

      expect(result, hasLength(1));
      expect(result.single.id, 2);
    });
  });
}
