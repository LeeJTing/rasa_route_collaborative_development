import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/model/data_models/local_food_data_model.dart';
import 'package:rasa_route_collaborative_development/model/data_models/local_food_image_data_model.dart';
import 'package:rasa_route_collaborative_development/model/data_models/local_food_preference_data_model.dart';
import 'package:rasa_route_collaborative_development/model/data_models/restaurant_item_data_model.dart';

void main() {
  test('local food data model mirrors only local_food columns', () {
    final LocalFoodDataModel data =
        LocalFoodDataModel.fromJson(<String, dynamic>{
          'local_food_id': 1,
          'food_name': 'Nasi Lemak',
          'food_category': 'Malay',
          'food_type': 'Food',
          'pronunciation_text': '[nah-see luh-mahk]',
          'audio_guide_url': 'pronunciation/1.mp3',
        });

    expect(data.foodName, 'Nasi Lemak');
    expect(data.foodCategory, 'Malay');
    expect(data.toJson(), isNot(contains('local_food_image')));
    expect(data.toJson(), isNot(contains('local_food_preference')));
  });

  test('local food image has its own table-shaped data model', () {
    final LocalFoodImageDataModel image =
        LocalFoodImageDataModel.fromJson(<String, dynamic>{
          'local_food_image_id': 3,
          'img_name': '1_nasi_lemak_1.jpg',
          'local_food_id': 1,
        });

    expect(image.localFoodImageId, 3);
    expect(image.imageName, '1_nasi_lemak_1.jpg');
    expect(image.localFoodId, 1);
  });

  test('local food preference link mirrors its junction table', () {
    final LocalFoodPreferenceDataModel link =
        LocalFoodPreferenceDataModel.fromJson(<String, dynamic>{
          'food_preference_id': 9,
          'local_food_id': 1,
          'is_main': true,
        });

    expect(link.foodPreferenceId, 9);
    expect(link.localFoodId, 1);
    expect(link.isMain, isTrue);
  });

  test('restaurant item model ignores joined local-food presentation data', () {
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
        },
      },
    );

    expect(data.restaurantItemPrice, 12.9);
    expect(data.restaurantItemName, 'Nasi Lemak Special');
    expect(data.toJson(), isNot(contains('local_food')));
  });
}
