import '../../domain_model/local_food.dart';
import '../../shared_client/api_manager/api_manager.dart';
import '../data_models/local_food_data_model.dart';

/// Remote-first access to the local-food catalogue.
///
/// The development Supabase project currently contains no catalogue rows, so
/// this repository supplies the same sample dishes shown in Figma whenever the
/// remote result is empty or unavailable. Presentation layers remain unaware
/// of where the data came from.
class FoodKnowledgeRepository {
  FoodKnowledgeRepository();

  final APIManager api = APIManager();

  static const String _selectColumns = '''
    local_food_id,
    food_name,
    description,
    origin,
    cultural_background,
    ingredients,
    food_category,
    cooking_style,
    meal_type,
    food_type,
    pronunciation_text,
    audio_guide_url,
    synonyms,
    local_food_image(img_name),
    local_food_preference(is_main, food_preference(preferred_taste))
  ''';

  final Set<int> _demoFavouriteIds = <int>{1, 2};
  bool _usingDemoData = false;

  Future<List<LocalFood>> getFoods() async {
    try {
      final List<Map<String, dynamic>> rows = await api.selectAll(
        APIManager.tableLocalFood,
        columns: _selectColumns,
        orderBy: 'food_name',
      );
      if (rows.isNotEmpty) {
        _usingDemoData = false;
        final Set<int> favouriteIds = await _getFavouriteFoodIds();
        return rows
            .map(LocalFoodDataModel.fromJson)
            .map(
              (LocalFoodDataModel data) => data.toDomain(
                isFavourite: favouriteIds.contains(data.localFoodId),
              ),
            )
            .toList(growable: false);
      }
    } catch (_) {
      // The offline/demo path below is intentional for development builds.
    }

    _usingDemoData = true;
    return _demoFoods
        .map(
          (LocalFood food) =>
              food.copyWith(isFavourite: _demoFavouriteIds.contains(food.id)),
        )
        .toList(growable: false);
  }

  Future<List<LocalFood>> searchFoods(String query) async {
    final String normalized = query.trim().toLowerCase();
    final List<LocalFood> foods = await getFoods();
    return foods
        .where(
          (LocalFood food) =>
              food.name.toLowerCase().contains(normalized) ||
              food.description.toLowerCase().contains(normalized),
        )
        .toList(growable: false);
  }

  Future<LocalFood?> getFoodById(int foodId) async {
    try {
      final Map<String, dynamic>? row = await api.selectOne(
        APIManager.tableLocalFood,
        columns: _selectColumns,
        eq: <String, Object?>{'local_food_id': foodId},
      );
      if (row != null) {
        _usingDemoData = false;
        return LocalFoodDataModel.fromJson(
          row,
        ).toDomain(isFavourite: await _isFavourite(foodId));
      }
    } catch (_) {
      // Fall through to the development catalogue.
    }

    _usingDemoData = true;
    for (final LocalFood food in _demoFoods) {
      if (food.id == foodId) {
        return food.copyWith(isFavourite: _demoFavouriteIds.contains(food.id));
      }
    }
    return null;
  }

  Future<void> toggleFavourite(int localFoodId) async {
    if (_usingDemoData || api.currentUserId.isEmpty) {
      _toggleDemoFavourite(localFoodId);
      return;
    }

    try {
      final bool isFavourite = await _isFavourite(localFoodId);
      if (isFavourite) {
        await api.deleteRows(
          APIManager.tableFavouriteFood,
          eq: <String, Object?>{
            'tourist_id': api.currentUserId,
            'local_food_id': localFoodId,
          },
        );
      } else {
        await api.insertRow(APIManager.tableFavouriteFood, <String, dynamic>{
          'tourist_id': api.currentUserId,
          'local_food_id': localFoodId,
        });
      }
    } catch (_) {
      _usingDemoData = true;
      _toggleDemoFavourite(localFoodId);
    }
  }

  void _toggleDemoFavourite(int localFoodId) {
    if (!_demoFavouriteIds.remove(localFoodId)) {
      _demoFavouriteIds.add(localFoodId);
    }
  }

  Future<Set<int>> _getFavouriteFoodIds() async {
    final String userId = api.currentUserId;
    if (userId.isEmpty) return <int>{};

    final List<Map<String, dynamic>> rows = await api.selectAll(
      APIManager.tableFavouriteFood,
      columns: 'local_food_id',
      eq: <String, Object?>{'tourist_id': userId},
    );
    return rows
        .map((Map<String, dynamic> row) => row['local_food_id'])
        .whereType<num>()
        .map((num id) => id.toInt())
        .toSet();
  }

  Future<bool> _isFavourite(int localFoodId) async {
    if (_usingDemoData) return _demoFavouriteIds.contains(localFoodId);
    return (await _getFavouriteFoodIds()).contains(localFoodId);
  }

  static const List<LocalFood> _demoFoods = <LocalFood>[
    LocalFood(
      id: 1,
      name: 'Prawn Noodle',
      description:
          'Yellow noodles and vermicelli in a rich red prawn-and-pork broth.',
      origin:
          'Created by Hokkien immigrant fishermen in Penang who used leftover prawn heads and shells to craft an intensely flavourful broth.',
      culturalBackground:
          'A Penang hawker classic also widely known as Har Mee or Penang Hokkien Mee.',
      ingredients:
          'Prawn heads and shells, pork bones, yellow noodles, rice vermicelli, boiled egg, kangkung, bean sprouts, chilli paste, fried shallots',
      category: 'Chinese',
      cookingStyle: 'Spicy, Savoury, Rich',
      mealType: 'All-Day Dining',
      foodType: 'Food',
      tastes: <String>['Spicy', 'Savoury', 'Rich'],
      mainTaste: 'Spicy',
      pronunciationText: '[har mee]',
      synonyms: <String>['Penang Hokkien Mee', 'Har Mee'],
      imageUrl: 'assets/images/figma/local_food_01.png',
    ),
    LocalFood(
      id: 2,
      name: 'Char Kway Teow',
      description:
          'Stir-fried flat rice noodles with prawns, egg, bean sprouts and chives.',
      origin: 'Penang',
      culturalBackground: 'A wok-fired Malaysian hawker favourite.',
      ingredients: 'Flat rice noodles, prawns, egg, bean sprouts, chives',
      category: 'Chinese',
      cookingStyle: 'Savoury',
      mealType: 'Street Food',
      foodType: 'Food',
      tastes: <String>['Savoury', 'Smoky'],
      mainTaste: 'Savoury',
      imageUrl: 'assets/images/figma/local_food_04.jpeg',
    ),
    LocalFood(
      id: 3,
      name: 'Roti Canai',
      description:
          'Crispy on the outside, soft and flaky on the inside. Best with curry dhal.',
      origin: 'Peninsular Malaysia',
      culturalBackground: 'A beloved Malaysian-Indian flatbread.',
      ingredients: 'Flour, water, ghee, salt',
      category: 'Indian',
      cookingStyle: 'Salty',
      mealType: 'Supper',
      foodType: 'Food',
      tastes: <String>['Salty', 'Buttery'],
      mainTaste: 'Salty',
      imageUrl: 'assets/images/figma/local_food_02.png',
    ),
    LocalFood(
      id: 4,
      name: 'Curry Laksa',
      description: 'Spicy and tangy noodle soup with rich coconut-based broth.',
      origin: 'Malaysia',
      culturalBackground: 'A fragrant noodle dish with regional variations.',
      ingredients: 'Noodles, coconut milk, chilli, tofu puffs, prawns',
      category: 'Malay',
      cookingStyle: 'Spicy',
      mealType: 'Dinner',
      foodType: 'Food',
      tastes: <String>['Spicy', 'Creamy'],
      mainTaste: 'Spicy',
      imageUrl: 'assets/images/figma/local_food_06.png',
    ),
    LocalFood(
      id: 5,
      name: 'Hokkien Mee',
      description:
          'Thick yellow noodles stir-fried in dark soy sauce, pork lard and cabbage.',
      origin: 'Kuala Lumpur',
      culturalBackground: 'A dark, wok-fried namesake of Penang prawn mee.',
      ingredients: 'Yellow noodles, dark soy sauce, pork lard, cabbage',
      category: 'Chinese',
      cookingStyle: 'Savoury',
      mealType: 'Street Food',
      foodType: 'Food',
      tastes: <String>['Savoury', 'Smoky'],
      mainTaste: 'Savoury',
      imageUrl: 'assets/images/figma/detail_09.png',
    ),
    LocalFood(
      id: 6,
      name: 'Teh Tarik',
      description:
          'Creamy pulled milk tea that balances rich chilli-paste spices.',
      origin: 'Malaysia',
      culturalBackground: 'Malaysia’s iconic pulled tea.',
      ingredients: 'Black tea, condensed milk',
      category: 'Malay',
      cookingStyle: 'Creamy',
      mealType: 'All-Day Dining',
      foodType: 'Beverage',
      tastes: <String>['Sweet', 'Creamy'],
      mainTaste: 'Sweet',
      imageUrl: 'assets/images/figma/restaurant_04.png',
    ),
    LocalFood(
      id: 7,
      name: 'Cendol',
      description:
          'Shaved ice with coconut milk, green rice jelly and palm sugar syrup.',
      origin: 'Southeast Asia',
      culturalBackground: 'A cooling Malaysian dessert.',
      ingredients: 'Shaved ice, coconut milk, rice jelly, palm sugar',
      category: 'Nyonya',
      cookingStyle: 'Sweet',
      mealType: 'High Tea',
      foodType: 'Dessert',
      tastes: <String>['Sweet', 'Refreshing'],
      mainTaste: 'Sweet',
      imageUrl: 'assets/images/figma/detail_05.png',
    ),
    LocalFood(
      id: 8,
      name: 'Bubur Cha Cha',
      description:
          'Coconut-milk dessert with sweet potato, taro and chewy sago pearls.',
      origin: 'Nyonya cuisine',
      culturalBackground: 'A colourful Peranakan dessert.',
      ingredients: 'Coconut milk, sweet potato, taro, sago',
      category: 'Nyonya',
      cookingStyle: 'Stewed',
      mealType: 'High Tea',
      foodType: 'Dessert',
      tastes: <String>['Sweet', 'Creamy'],
      mainTaste: 'Sweet',
      imageUrl: 'assets/images/figma/detail_07.png',
    ),
    LocalFood(
      id: 9,
      name: 'Kolo Mee',
      description: 'Springy Sarawak noodles tossed in savoury aromatic oil.',
      origin: 'Sarawak',
      culturalBackground: 'A signature Kuching breakfast dish.',
      ingredients: 'Egg noodles, shallot oil, char siu, spring onion',
      category: 'Sarawak',
      cookingStyle: 'Savoury',
      mealType: 'Breakfast',
      foodType: 'Food',
      tastes: <String>['Savoury', 'Fragrant'],
      mainTaste: 'Savoury',
      imageUrl: 'assets/images/figma/detail_03.png',
    ),
    LocalFood(
      id: 10,
      name: 'Satay',
      description: 'Charcoal-grilled skewers served with peanut sauce.',
      origin: 'Malaysia',
      culturalBackground: 'A popular evening street-food dish.',
      ingredients: 'Marinated meat, spices, peanut sauce',
      category: 'Malay',
      cookingStyle: 'Roasted, Savoury',
      mealType: 'Dinner',
      foodType: 'Food',
      tastes: <String>['Roasted', 'Savoury', 'Smoky'],
      mainTaste: 'Roasted',
      imageUrl: 'assets/images/figma/detail_02.png',
    ),
  ];
}
