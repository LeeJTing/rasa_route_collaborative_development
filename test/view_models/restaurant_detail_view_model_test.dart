import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/discovery_logic_facade.dart';
import 'package:rasa_route_collaborative_development/view_models/restaurant_detail_view_model.dart';

import '../test_support/fake_discovery_logic_facade.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads a restaurant by id', () async {
    final FakeDiscoveryLogicFacade logic = FakeDiscoveryLogicFacade();
    final RestaurantDetailViewModel viewModel =
        _TestRestaurantDetailViewModel(logic);

    await viewModel.loadRestaurant(1);

    expect(viewModel.restaurant?.id, 1);
    expect(viewModel.restaurant?.name, 'OldTown Heritage Kitchen');

    viewModel.dispose();
  });

  test('surfaces a load failure', () async {
    final FakeDiscoveryLogicFacade logic = FakeDiscoveryLogicFacade(
      restaurant: null,
    );
    final RestaurantDetailViewModel viewModel =
        _TestRestaurantDetailViewModel(logic);

    await viewModel.loadRestaurant(999);

    expect(viewModel.hasError, isTrue);
    expect(viewModel.restaurant, isNull);

    viewModel.dispose();
  });
}

class _TestRestaurantDetailViewModel extends RestaurantDetailViewModel {
  _TestRestaurantDetailViewModel(this.logic);

  final DiscoveryLogicFacade logic;

  @override
  DiscoveryLogicFacade createDiscoveryLogic() => logic;
}
