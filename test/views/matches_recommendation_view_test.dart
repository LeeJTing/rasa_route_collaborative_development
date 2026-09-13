import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/app/theme/app_theme.dart';
import 'package:rasa_route_collaborative_development/app/routing/app_routes.dart';
import 'package:rasa_route_collaborative_development/domain_model/matches_recommendation.dart';
import 'package:rasa_route_collaborative_development/domain_model/restaurant.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/discovery_logic_facade.dart';
import 'package:rasa_route_collaborative_development/view_models/dashboard_view_model.dart';
import 'package:rasa_route_collaborative_development/view_models/matches_recommendation_view_model.dart';
import 'package:rasa_route_collaborative_development/views/matches_recommendation_view/matches_recommendation_view.dart';

import '../test_support/fake_discovery_logic_facade.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows both recommendation tabs and switches to landmarks', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: _TestMatchesRecommendationView(FakeDiscoveryLogicFacade()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Matches'), findsOneWidget);
    expect(find.text('Restaurants'), findsOneWidget);
    expect(find.text('Submitted Landmarks'), findsOneWidget);
    expect(find.text('Prawn Noodle'), findsWidgets);
    expect(find.text('OldTown Heritage Kitchen'), findsOneWidget);
    expect(find.text('Halal'), findsNothing);

    await tester.tap(find.text('Price'));
    await tester.pump();
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);

    await tester.tap(find.text('Price'));
    await tester.pump();
    expect(find.byIcon(Icons.arrow_downward), findsOneWidget);

    final Finder foodToggle = find.byKey(
      const ValueKey<String>('matched-food-1-toggle'),
    );
    await tester.tap(foodToggle);
    await tester.pumpAndSettle();
    expect(find.text('OldTown Heritage Kitchen'), findsNothing);

    await tester.tap(foodToggle);
    await tester.pumpAndSettle();
    expect(find.text('OldTown Heritage Kitchen'), findsOneWidget);

    final Finder groupSeeMore = find.byKey(
      const ValueKey<String>('matched-food-1-see-more'),
    );
    expect(groupSeeMore, findsOneWidget);
    await tester.ensureVisible(groupSeeMore);
    await tester.pumpAndSettle();
    await tester.tap(groupSeeMore);
    await tester.pumpAndSettle();
    expect(find.text('Heritage Noodle House'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('matched-food-1-show-less')),
      findsOneWidget,
    );

    await tester.tap(find.text('Submitted Landmarks'));
    await tester.pump();

    expect(find.text('Uncle Lim Prawn Noodle Stall'), findsOneWidget);
    expect(find.text('User Submitted Landmark'), findsWidgets);
    // Restaurant-card furniture: the price/serves bar and the full-width
    // action, so both tabs read the same.
    expect(find.text('Serves Prawn Noodle'), findsOneWidget);
    expect(find.text('From RM 12.00'), findsOneWidget);
    expect(find.text('Jalan Pudu, Kuala Lumpur'), findsOneWidget);
    expect(find.text('Halal'), findsNothing);
    expect(find.text('Name'), findsOneWidget);

    await tester.tap(find.text('Name'));
    await tester.pump();
    expect(find.byIcon(Icons.arrow_upward), findsOneWidget);

    await tester.tap(find.text('Name'));
    await tester.pump();
    expect(find.byIcon(Icons.arrow_downward), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fits a narrow phone and opens full landmark details', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    MapSelectionHandoff().pendingLandmarkId = null;
    addTearDown(() => MapSelectionHandoff().pendingLandmarkId = null);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: _TestMatchesRecommendationView(FakeDiscoveryLogicFacade()),
        routes: <String, WidgetBuilder>{
          AppRoutes.landmarkPlaceDetail: (BuildContext context) => Scaffold(
            body: Text('Landmark ${MapSelectionHandoff().takeLandmarkId()}'),
          ),
        },
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Submitted Landmarks'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('View Landmark Details'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View Landmark Details'));
    await tester.pumpAndSettle();

    expect(find.text('Landmark 901'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opens food details and can remove a liked food group', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        onGenerateRoute: (RouteSettings settings) {
          if (settings.name == AppRoutes.foodDetail) {
            return MaterialPageRoute<void>(
              builder: (_) =>
                  Scaffold(body: Text('Food detail ${settings.arguments}')),
            );
          }
          return null;
        },
        home: _TestMatchesRecommendationView(FakeDiscoveryLogicFacade()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('matched-food-1-details')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Food detail 1'), findsOneWidget);

    Navigator.of(tester.element(find.text('Food detail 1'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('matched-food-1-like')));
    await tester.pumpAndSettle();
    expect(find.text('No matched foods yet'), findsOneWidget);
  });

  testWidgets('shows a group empty state without a runtime type error', (
    WidgetTester tester,
  ) async {
    const MatchesRecommendationResult emptyRecommendations =
        MatchesRecommendationResult(
          stateCode: 'KUL',
          stateName: 'Kuala Lumpur',
          session: testSwipeSession,
          groups: <MatchedFoodRecommendations>[
            MatchedFoodRecommendations(
              food: testMatchedFood,
              restaurants: <Restaurant>[],
              submittedLandmarks: <SubmittedLandmarkRecommendation>[],
            ),
          ],
        );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: _TestMatchesRecommendationView(
          FakeDiscoveryLogicFacade(matchesResult: emptyRecommendations),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('No matching restaurants'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _TestMatchesRecommendationViewModel
    extends MatchesRecommendationViewModel {
  _TestMatchesRecommendationViewModel(this.logic);

  final DiscoveryLogicFacade logic;

  @override
  DiscoveryLogicFacade createDiscoveryLogic() => logic;
}

class _TestMatchesRecommendationView extends MatchesRecommendationView {
  const _TestMatchesRecommendationView(this.logic);

  final DiscoveryLogicFacade logic;

  @override
  MatchesRecommendationViewModel createViewModel() =>
      _TestMatchesRecommendationViewModel(logic);
}
