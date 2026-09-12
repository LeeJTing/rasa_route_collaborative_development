import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/app/theme/app_theme.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/discovery_logic_facade.dart';
import 'package:rasa_route_collaborative_development/view_models/restaurant_detail_view_model.dart';
import 'package:rasa_route_collaborative_development/views/restaurant_detail_view/restaurant_detail_view.dart';

import '../test_support/fake_discovery_logic_facade.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows restaurant details', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: _TestRestaurantDetailView(FakeDiscoveryLogicFacade()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('OldTown Heritage Kitchen'), findsWidgets);
    expect(find.text('4.6'), findsOneWidget);
    expect(find.textContaining('reviews'), findsNothing);
    expect(find.text('Halal'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Local Foods Served (1)'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Local Foods Served (1)'), findsOneWidget);
    await tester.tap(find.text('Local Foods Served (1)'));
    await tester.pumpAndSettle();
    expect(
      find.text('A comforting local noodle dish in a rich prawn broth.'),
      findsOneWidget,
    );

    // Reporting now lives on a separate full-screen page that this button
    // opens (AppRoutes.reportPlace / ReportPlaceView). The button simply
    // needs to be present here.
    expect(find.text('Report Restaurant'), findsOneWidget);
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
