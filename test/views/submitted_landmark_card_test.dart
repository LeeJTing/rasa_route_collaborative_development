import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/matches_recommendation.dart';
import 'package:rasa_route_collaborative_development/views/restaurant_recommendation_view/widgets/submitted_landmark_card.dart';

/// The Quick Mode landmark card must read like the restaurant card - same
/// header shape, one metric row, category worded like the restaurant rows -
/// with the ONE difference being the rating, which a submitted landmark does
/// not have (user request, 2026-09-13).
void main() {
  SubmittedLandmarkRecommendation landmark({String category = 'Chinese'}) =>
      SubmittedLandmarkRecommendation(
        id: 7,
        name: 'HOMETOWN ICE KACANG',
        category: category,
        distanceMetres: 350,
        dishes: const <SubmittedLandmarkDish>[],
      );

  Future<void> pumpCard(
    WidgetTester tester, {
    String category = 'Chinese',
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SubmittedLandmarkCard(
            landmark: landmark(category: category),
            expanded: false,
            onExpand: () {},
            onTap: () {},
            onImageTap: (String? source, String semanticLabel) {},
          ),
        ),
      ),
    );
  }

  testWidgets('shows the restaurant-style category and never a rating', (
    WidgetTester tester,
  ) async {
    await pumpCard(tester);

    expect(find.text('Chinese Restaurant'), findsOneWidget);
    expect(find.byIcon(Icons.star), findsNothing);
    expect(find.text('350 m'), findsOneWidget);
  });

  testWidgets('uses the placeholder wording when no category is recorded', (
    WidgetTester tester,
  ) async {
    await pumpCard(tester, category: '');

    expect(find.text('Submitted Landmark'), findsOneWidget);
  });

  testWidgets('an expanded dish shows its description, not its ingredients', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SubmittedLandmarkCard(
            landmark: const SubmittedLandmarkRecommendation(
              id: 7,
              name: 'Restoran Ariana',
              category: 'Indian',
              distanceMetres: 32,
              dishes: <SubmittedLandmarkDish>[
                SubmittedLandmarkDish(
                  name: 'Roti Canai',
                  price: 4,
                  ingredients: 'Wheat flatbread, Bread, Lentils, Fish',
                  description:
                      'Flaky, crispy stretched Indian flatbread cooked on '
                      'griddle, served with dhal lentil or fish curry',
                ),
              ],
            ),
            expanded: true,
            onExpand: () {},
            onTap: () {},
            onImageTap: (String? source, String semanticLabel) {},
          ),
        ),
      ),
    );

    // The grey line reads like a restaurant menu row's description; the
    // recorded ingredients list never shows while a description exists
    // (user request, 2026-09-14).
    expect(
      find.text(
        'Flaky, crispy stretched Indian flatbread cooked on griddle, '
        'served with dhal lentil or fish curry',
      ),
      findsOneWidget,
    );
    expect(find.text('Wheat flatbread, Bread, Lentils, Fish'), findsNothing);
  });
}
