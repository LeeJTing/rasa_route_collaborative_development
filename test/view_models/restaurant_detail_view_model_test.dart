import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/restaurant_report_reason.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/discovery_logic_facade.dart';
import 'package:rasa_route_collaborative_development/view_models/restaurant_detail_view_model.dart';

import '../test_support/fake_discovery_logic_facade.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads a restaurant and records local report UI state', () async {
    final RestaurantDetailViewModel viewModel =
        _TestRestaurantDetailViewModel(FakeDiscoveryLogicFacade());

    await viewModel.loadRestaurant(1);

    expect(viewModel.restaurant?.id, 1);
    expect(viewModel.reportSubmitted, isFalse);

    await viewModel.submitReport(RestaurantReportReason.incorrectLocation);
    expect(viewModel.reportSubmitted, isTrue);

    viewModel.consumeReportSubmitted();
    expect(viewModel.reportSubmitted, isFalse);

    viewModel.dispose();
  });
}

class _TestRestaurantDetailViewModel extends RestaurantDetailViewModel {
  _TestRestaurantDetailViewModel(this.logic);

  final DiscoveryLogicFacade logic;

  @override
  DiscoveryLogicFacade createDiscoveryLogic() => logic;
}
