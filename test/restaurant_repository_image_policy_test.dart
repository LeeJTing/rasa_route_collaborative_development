import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/restaurant_item.dart';
import 'package:rasa_route_collaborative_development/model/repositories/restaurant_repository.dart';

void main() {
  group('restaurant item image policy', () {
    final RestaurantRepository repository = RestaurantRepository();

    test('prefers the restaurant-specific image', () {
      expect(
        repository.preferredRestaurantItemImageName(
          restaurantImageName: 'restaurant-item.jpg',
          linkedFoodImageNames: <String>['catalogue.jpg'],
        ),
        'restaurant-item.jpg',
      );
    });

    test(
      'uses the image from the linked local food when item image is absent',
      () {
        expect(
          repository.preferredRestaurantItemImageName(
            restaurantImageName: null,
            linkedFoodImageNames: <String>[
              '040_yong_tau_foo_1.jpg',
              '040_yong_tau_foo_2.jpg',
            ],
          ),
          '040_yong_tau_foo_1.jpg',
        );
      },
    );

    test('returns null only when neither relationship provides an image', () {
      expect(
        repository.preferredRestaurantItemImageName(
          restaurantImageName: ' ',
          linkedFoodImageNames: const <String>[],
        ),
        isNull,
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
