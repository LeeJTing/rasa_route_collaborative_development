import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/restaurant_report_reason.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/discovery_logic_facade.dart';
import 'package:rasa_route_collaborative_development/view_models/restaurant_detail_view_model.dart';

import '../test_support/fake_discovery_logic_facade.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads a restaurant and records a new report', () async {
    final FakeDiscoveryLogicFacade logic = FakeDiscoveryLogicFacade();
    final RestaurantDetailViewModel viewModel =
        _TestRestaurantDetailViewModel(logic);

    await viewModel.loadRestaurant(1);

    expect(viewModel.restaurant?.id, 1);
    expect(viewModel.reportSubmitted, isFalse);

    await viewModel.submitReport(RestaurantReportReason.incorrectLocation);
    expect(viewModel.reportSubmitted, isTrue);
    expect(viewModel.alreadyReported, isFalse);
    expect(viewModel.reportFailed, isFalse);

    viewModel.consumeReportSubmitted();
    expect(viewModel.reportSubmitted, isFalse);
    expect(viewModel.alreadyReported, isFalse);
    expect(viewModel.reportFailed, isFalse);

    viewModel.dispose();
  });

  test('flags a duplicate report without counting it again', () async {
    final FakeDiscoveryLogicFacade logic = FakeDiscoveryLogicFacade()
      ..duplicateReport = true;
    final RestaurantDetailViewModel viewModel =
        _TestRestaurantDetailViewModel(logic);

    await viewModel.loadRestaurant(1);
    await viewModel.submitReport(RestaurantReportReason.listedLocalFoodUnavailable);

    expect(viewModel.alreadyReported, isTrue);
    expect(viewModel.reportSubmitted, isFalse);

    viewModel.dispose();
  });

  test('flags a backend failure instead of confirming the report', () async {
    final FakeDiscoveryLogicFacade logic = FakeDiscoveryLogicFacade()
      ..failReport = true;
    final RestaurantDetailViewModel viewModel =
        _TestRestaurantDetailViewModel(logic);

    await viewModel.loadRestaurant(1);
    await viewModel.submitReport(RestaurantReportReason.noLongerExists);

    expect(viewModel.reportFailed, isTrue);
    expect(viewModel.reportSubmitted, isFalse);
    expect(viewModel.alreadyReported, isFalse);

    viewModel.dispose();
  });

  test('asks a signed-out tourist to sign in before counting a report',
      () async {
    final FakeDiscoveryLogicFacade logic = FakeDiscoveryLogicFacade()
      ..requireSignIn = true;
    final RestaurantDetailViewModel viewModel =
        _TestRestaurantDetailViewModel(logic);

    await viewModel.loadRestaurant(1);
    await viewModel.submitReport(RestaurantReportReason.incorrectLocation);

    expect(viewModel.requiresSignIn, isTrue);
    expect(viewModel.reportSubmitted, isFalse);
    expect(viewModel.alreadyReported, isFalse);
    expect(viewModel.reportFailed, isFalse);

    viewModel.consumeReportSubmitted();
    expect(viewModel.requiresSignIn, isFalse);

    viewModel.dispose();
  });

  test('flags when the report froze the restaurant so the View leaves the map',
      () async {
    final FakeDiscoveryLogicFacade logic = FakeDiscoveryLogicFacade()
      ..frozePlace = true;
    final RestaurantDetailViewModel viewModel =
        _TestRestaurantDetailViewModel(logic);

    await viewModel.loadRestaurant(1);
    await viewModel.submitReport(RestaurantReportReason.incorrectLocation);

    expect(viewModel.reportSubmitted, isTrue);
    expect(viewModel.reportFrozePlace, isTrue);
    expect(viewModel.alreadyReported, isFalse);

    viewModel.consumeReportSubmitted();
    expect(viewModel.reportFrozePlace, isFalse);
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
