import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/app/theme/app_theme.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/discovery_logic_facade.dart';
import 'package:rasa_route_collaborative_development/view_models/restaurant_detail_view_model.dart';
import 'package:rasa_route_collaborative_development/views/restaurant_detail_view/restaurant_detail_view.dart';

import '../test_support/fake_discovery_logic_facade.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows restaurant details and completes the report UI flow', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: _TestRestaurantDetailView(FakeDiscoveryLogicFacade()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('OldTown Heritage Kitchen'), findsWidgets);
    expect(find.text('Halal'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Report Restaurant'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Local Foods Served'), findsOneWidget);
    await tester.tap(find.text('Report Restaurant'));
    await tester.pumpAndSettle();

    expect(find.text('Incorrect Location'), findsOneWidget);
    expect(find.text('Submit Report'), findsOneWidget);

    await tester.tap(find.text('Incorrect Location'));
    await tester.pump();
    await tester.tap(find.text('Submit Report'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Report received. Thank you for helping keep the map accurate.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}

class _TestRestaurantDetailViewModel extends RestaurantDetailViewModel {
  _TestRestaurantDetailViewModel(this.logic);

  final DiscoveryLogicFacade logic;

  @override
  DiscoveryLogicFacade createDiscoveryLogic() => logic;
}

class _TestRestaurantDetailView extends RestaurantDetailView {
  const _TestRestaurantDetailView(this.logic);

  final DiscoveryLogicFacade logic;

  @override
  RestaurantDetailViewModel createViewModel() =>
      _TestRestaurantDetailViewModel(logic);

  @override
  int? selectedRestaurantId(BuildContext context) => 1;
}
