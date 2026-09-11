import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/model/data_models/food_analysis_response.dart';

FoodAnalysisResponse _response({String pronunciation = ''}) =>
    FoodAnalysisResponse(
      dish: 'Nasi Lemak',
      variant: 'Nasi Lemak Biasa',
      description: 'Coconut rice with sambal, peanuts, anchovies and egg.',
      origin: 'Melaka & Negeri Sembilan',
      cookingStyle: 'Simmering',
      mealType: 'Breakfast',
      foodCategory: 'Malay',
      isMalaysianLocalFood: true,
      culturalBackground: '',
      foodStatus: 'detected',
      foodImageStatus: 'complete',
      confidence: 0.95,
      pronunciation: pronunciation,
    );

void main() {
  test('pronunciation is serialised in toJson', () {
    expect(
      _response(pronunciation: 'nah-see luh-mak').toJson()['pronunciation'],
      'nah-see luh-mak',
    );
  });

  test('pronunciation defaults to empty', () {
    expect(_response().pronunciation, '');
    expect(_response().toJson()['pronunciation'], '');
  });

  test('pronunciation survives copyWith and can be replaced', () {
    expect(
      _response(pronunciation: 'nah-see luh-mak').copyWith().pronunciation,
      'nah-see luh-mak',
    );
    expect(
      _response(
        pronunciation: 'nah-see luh-mak',
      ).copyWith(pronunciation: 'roh-tee chah-nai').pronunciation,
      'roh-tee chah-nai',
    );
  });
}
