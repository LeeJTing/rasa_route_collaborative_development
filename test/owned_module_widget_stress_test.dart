import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/local_food.dart';
import 'package:rasa_route_collaborative_development/domain_model/restaurant.dart';
import 'package:rasa_route_collaborative_development/domain_model/restaurant_item.dart';
import 'package:rasa_route_collaborative_development/view_models/local_food_list_view_model.dart';
import 'package:rasa_route_collaborative_development/views/food_detail_view/widgets/food_hero_card.dart';
import 'package:rasa_route_collaborative_development/views/food_detail_view/widgets/food_overview_card.dart';
import 'package:rasa_route_collaborative_development/views/local_food_list_view/widgets/food_search_bar.dart';
import 'package:rasa_route_collaborative_development/views/local_food_list_view/widgets/local_food_card.dart';
import 'package:rasa_route_collaborative_development/views/restaurant_recommendation_view/widgets/restaurant_card.dart';

void main() {
  group('owned-module hostile input', () {
    testWidgets('caps pasted search without retaining an invisible tail', (
      WidgetTester tester,
    ) async {
      final TextEditingController controller = TextEditingController();
      addTearDown(controller.dispose);
      String latest = '';
      await tester.pumpWidget(
        _host(
          FoodSearchBar(
            controller: controller,
            onChanged: (String value) => latest = value,
            maxLength: LocalFoodListViewModel.maximumSearchLength,
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'x' * 10000);
      await tester.pump();

      expect(
        controller.text.length,
        LocalFoodListViewModel.maximumSearchLength,
      );
      expect(latest.length, LocalFoodListViewModel.maximumSearchLength);
      expect(tester.takeException(), isNull);
    });

    test('ViewModel caps programmatic Unicode search input safely', () {
      final LocalFoodListViewModel viewModel = LocalFoodListViewModel();
      addTearDown(viewModel.dispose);

      viewModel.updateSearch('${'🥥' * 1000} nasi lemak');

      expect(
        viewModel.query.runes.length,
        LocalFoodListViewModel.maximumSearchLength,
      );
      expect(viewModel.displayedFoods, isEmpty);
    });

    testWidgets('food list card tolerates narrow screens and extreme text', (
      WidgetTester tester,
    ) async {
      await _setCompactSurface(tester);
      await tester.pumpWidget(
        _host(
          SingleChildScrollView(
            child: LocalFoodCard(
              food: _food(
                name: 'VeryLongUnbrokenFoodName' * 20,
                description: 'Description ' * 200,
                category: 'Category' * 20,
                mealType: 'All-Day Dining ' * 20,
                mainTaste: 'Savoury' * 20,
              ),
              isSelecting: false,
              isSelected: false,
              onTap: () {},
              onFavourite: () {},
            ),
          ),
          textScale: 2,
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('food overview tolerates long database strings', (
      WidgetTester tester,
    ) async {
      await _setCompactSurface(tester);
      await tester.pumpWidget(
        _host(
          SingleChildScrollView(
            child: FoodOverviewCard(
              food: _food(
                name: 'Prawn Noodle ' * 40,
                category: 'Chinese ' * 30,
                mealType: 'All-Day Dining ' * 20,
                foodType: 'Food ' * 30,
                tastes: <String>['Spicy ' * 30, 'Savoury ' * 30],
                synonyms: <String>['Penang Hokkien Mee ' * 50],
              ),
              onPlayPronunciation: () {},
              isStartingPronunciation: false,
            ),
          ),
          textScale: 2,
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('restaurant card tolerates extreme names, counts and menu', (
      WidgetTester tester,
    ) async {
      await _setCompactSurface(tester);
      final RestaurantItem item = RestaurantItem(
        id: 1,
        restaurantId: 1,
        localFoodId: 1,
        foodName: 'Noodle with Yong Tau Foo ' * 30,
        ingredients: 'Ingredient ' * 150,
        price: 999999999999.99,
        currency: 'RM',
        foodCategory: 'Chinese',
      );
      await tester.pumpWidget(
        _host(
          SingleChildScrollView(
            child: RestaurantCard(
              restaurant: Restaurant(
                id: 1,
                name: 'Extremely Long Restaurant Name ' * 20,
                category: 'Malaysian Chinese Restaurant ' * 20,
                address: '',
                rating: 4.6,
                reviewCount: 999999999,
                phone: '',
                website: '',
                openingHours: const [],
                items: <RestaurantItem>[item],
              ),
              distanceLabel: '999999999999.9 km',
              expanded: true,
              onExpand: () {},
              onTap: () {},
              onFoodImageTap: (_) {},
            ),
          ),
          textScale: 2,
        ),
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('image index resets when Food Detail switches dishes', (
      WidgetTester tester,
    ) async {
      int tappedIndex = -1;
      Widget card(LocalFood food) => _host(
        FoodHeroCard(
          food: food,
          isLiked: false,
          isUpdatingFavourite: false,
          onLike: () {},
          onImageTap: (int index) => tappedIndex = index,
        ),
      );

      await tester.pumpWidget(
        card(_food(id: 1, imageUrls: const <String>['bad-a', 'bad-b'])),
      );
      await tester.drag(find.byType(PageView), const Offset(-300, 0));
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        card(_food(id: 2, imageUrls: const <String>['bad-c'])),
      );
      await tester.tap(find.byType(InkWell).first);

      expect(tappedIndex, 0);
      expect(tester.takeException(), isNull);
    });
  });
}

Widget _host(Widget child, {double textScale = 1}) => MaterialApp(
  builder: (BuildContext context, Widget? child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(textScale)),
    child: child!,
  ),
  home: Scaffold(body: Center(child: child)),
);

Future<void> _setCompactSurface(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(320, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

LocalFood _food({
  int id = 1,
  String name = 'Prawn Noodle',
  String description = 'Description',
  String category = 'Chinese',
  String mealType = 'All-Day Dining',
  String foodType = 'Food',
  String mainTaste = 'Savoury',
  List<String> tastes = const <String>['Savoury'],
  List<String> synonyms = const <String>[],
  List<String> imageUrls = const <String>[],
}) => LocalFood(
  id: id,
  name: name,
  description: description,
  origin: 'Origin',
  culturalBackground: 'Background',
  ingredients: 'Ingredients',
  category: category,
  cookingStyle: 'Boiled',
  mealType: mealType,
  foodType: foodType,
  tastes: tastes,
  mainTaste: mainTaste,
  pronunciationText: 'har mee',
  synonyms: synonyms,
  imageUrls: imageUrls,
);
