import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/model/data_models/local_food_data_model.dart';
import 'package:rasa_route_collaborative_development/model/data_models/restaurant_item_data_model.dart';

void main() {
  test('local food keeps every Supabase gallery image in stable order', () {
    final LocalFoodDataModel data = LocalFoodDataModel.fromJson(
      <String, dynamic>{
        'local_food_id': 1,
        'food_name': 'Nasi Lemak',
        'local_food_image': <Map<String, dynamic>>[
          <String, dynamic>{'img_name': '1_nasi_lemak_3.jpg'},
          <String, dynamic>{'img_name': '1_nasi_lemak_1.jpg'},
          <String, dynamic>{'img_name': '1_nasi_lemak_2.jpg'},
        ],
      },
    );

    expect(data.imageUrls, <String>[
      '1_nasi_lemak_1.jpg',
      '1_nasi_lemak_2.jpg',
      '1_nasi_lemak_3.jpg',
    ]);
    expect(data.toDomain().imageUrl, '1_nasi_lemak_1.jpg');
  });

  test('restaurant item reads its linked local food fallback content', () {
    final RestaurantItemDataModel data = RestaurantItemDataModel.fromJson(
      <String, dynamic>{
        'restaurant_item_id': 10,
        'restaurant_id': 5,
        'local_food_id': 1,
        'restaurant_item_name': 'Nasi Lemak Special',
        'restaurant_item_price': '12.90',
        'local_food': <String, dynamic>{
          'food_name': 'Nasi Lemak',
          'description': 'Coconut rice with sambal.',
          'local_food_image': <Map<String, dynamic>>[
            <String, dynamic>{'img_name': '1_nasi_lemak_1.jpg'},
          ],
        },
      },
    );

    expect(data.restaurantItemPrice, 12.9);
    expect(data.localFoodName, 'Nasi Lemak');
    expect(data.localFoodDescription, 'Coconut rice with sambal.');
    expect(data.localFoodImageName, '1_nasi_lemak_1.jpg');
  });
}
