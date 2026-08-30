import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/app/routing/app_navigator.dart';
import 'package:rasa_route_collaborative_development/app/routing/app_routes.dart';
import 'package:rasa_route_collaborative_development/domain_model/map.dart';
import 'package:rasa_route_collaborative_development/view_models/dashboard_view_model.dart';

void main() {
  testWidgets('opens restaurant details with the selected pin id', (
    WidgetTester tester,
  ) async {
    final DashboardViewModel viewModel = DashboardViewModel();
    addTearDown(viewModel.dispose);

    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: AppNavigator.navigatorKey,
        routes: <String, WidgetBuilder>{
          AppRoutes.restaurantDetail: (BuildContext context) {
            final Object? argument = ModalRoute.of(context)?.settings.arguments;
            return Scaffold(body: Text('Restaurant $argument'));
          },
        },
        home: const Scaffold(body: Text('Map')),
      ),
    );

    viewModel.selectPin(
      const MapPin(
        referenceId: '42',
        kind: MapPinKind.restaurant,
        latitude: 3.1,
        longitude: 101.7,
        label: 'Selected Restaurant',
        weight: 1,
      ),
    );
    viewModel.openSelectedPin();
    await tester.pumpAndSettle();

    expect(find.text('Restaurant 42'), findsOneWidget);
  });
}
