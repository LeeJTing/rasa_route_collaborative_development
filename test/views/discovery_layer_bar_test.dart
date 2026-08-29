import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/local_food.dart';
import 'package:rasa_route_collaborative_development/views/dashboard_view/widgets/discovery_layer_bar.dart';

void main() {
  testWidgets('navigates cards and likes the Target Frame food', (
    WidgetTester tester,
  ) async {
    int previousCount = 0;
    int nextCount = 0;
    int likeCount = 0;
    int heartCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              // Reproduces the narrow constraint from the reported phone log.
              width: 344,
              child: DiscoveryLayerBar(
                contextLabel: 'Showing Nasi Lemak',
                matchesCount: 0,
                onMatchesTap: () {},
                expanded: true,
                onToggle: () {},
                currentFood: _food(1, 'Nasi Lemak'),
                previousFood: _food(2, 'Cendol'),
                nextFood: _food(3, 'Curry Mee'),
                currentFoodRestricted: false,
                currentFoodLiked: false,
                loading: false,
                errorMessage: null,
                showResumePrompt: false,
                stateName: 'Selangor',
                savedCardCount: 0,
                savedLikeCount: 0,
                savedRestaurantCount: 0,
                likeRevision: 0,
                onPrevious: () => previousCount++,
                onNext: () => nextCount++,
                onFoodTap: (_) {},
                onLike: () => likeCount++,
                onHeartTap: () => heartCount++,
                onContinue: () {},
                onStartNew: () {},
              ),
            ),
          ),
        ),
      ),
    );

    final Finder target = find.byKey(const Key('swipe-target-card'));
    expect(find.text('Nasi Lemak'), findsOneWidget);
    await tester.tap(target);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(target);
    await tester.pumpAndSettle();
    expect(likeCount, 1);

    final Finder heart = find.byKey(const Key('swipe-like-button'));
    final IconButton heartButton = tester.widget<IconButton>(heart);
    heartButton.onPressed!();
    await tester.pumpAndSettle();
    expect(likeCount, 1);
    expect(heartCount, 1);

    await tester.fling(target, const Offset(-240, 0), 800);
    await tester.pump();
    expect(nextCount, 1);

    await tester.fling(target, const Offset(240, 0), 800);
    await tester.pump();
    expect(previousCount, 1);
  });
}

LocalFood _food(int id, String name) => LocalFood(
  id: id,
  name: name,
  description: '$name description',
  origin: 'Malaysia',
  culturalBackground: '',
  ingredients: '',
  category: 'Local',
  cookingStyle: '',
  mealType: 'All Day',
  foodType: 'Food',
);
