import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/address_suggestion.dart';
import 'package:rasa_route_collaborative_development/domain_model/local_food.dart';
import 'package:rasa_route_collaborative_development/domain_model/tourist_location.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/landmark_logic_facade.dart';
import 'package:rasa_route_collaborative_development/view_models/add_landmark_view_model.dart';

LocalFood _food(String name) => LocalFood(
  id: 0,
  name: name,
  description: 'Description of $name',
  origin: 'Malaysia',
  culturalBackground: '',
  ingredients: '',
  category: 'Malay',
  cookingStyle: 'Frying',
  mealType: 'Breakfast',
  foodType: 'Food',
);

/// The captured spot the form anchors on (Kuala Lumpur city centre).
const TouristLocation _kl = TouristLocation(
  latitude: 3.1390,
  longitude: 101.6869,
);

/// ~40 m north of the capture spot - inside the 100 m pin range.
const TouristLocation _nearby = TouristLocation(
  latitude: 3.1393,
  longitude: 101.68695,
);

/// The facade seam: only the two geocoding calls are replaced. The distance,
/// range and validation rules stay the real logic.
class _FakeLandmarkLogicFacade extends LandmarkLogicFacade {
  /// `null` = the lookup failed; `[]` = nothing matched.
  List<AddressSuggestion>? searchResults;
  final List<String> searchQueries = <String>[];

  String? reverseAddress;
  final List<TouristLocation> reverseCalls = <TouristLocation>[];

  @override
  Future<List<AddressSuggestion>?> searchAddresses({
    required String query,
    required TouristLocation around,
  }) async {
    searchQueries.add(query);
    return searchResults;
  }

  @override
  Future<String?> reverseGeocodeAddress(TouristLocation location) async {
    reverseCalls.add(location);
    return reverseAddress;
  }
}

class _TestAddLandmarkViewModel extends AddLandmarkViewModel {
  _TestAddLandmarkViewModel(this.facade);

  final _FakeLandmarkLogicFacade facade;

  @override
  LandmarkLogicFacade createLandmarkLogic() => facade;
}

Future<_TestAddLandmarkViewModel> _form(_FakeLandmarkLogicFacade facade) async {
  final _TestAddLandmarkViewModel vm = _TestAddLandmarkViewModel(facade);
  await vm.onInit();
  vm.setRecognizedFood(_food('Cendol'), captureLocation: _kl);
  return vm;
}

/// Waits out both debounces (suggestion search + pin address lookup) and
/// lets their async completions land.
Future<void> _settle() async => Future<void>.delayed(
  AddLandmarkViewModel.addressSearchDebounce +
      AddLandmarkViewModel.mapAddressLookupDelay +
      const Duration(milliseconds: 250),
);

const AddressSuggestion _nearbySuggestion = AddressSuggestion(
  address: 'PV18 Residences, Setapak, 53000 Kuala Lumpur',
  latitude: 3.1393,
  longitude: 101.68695,
  distanceMeters: 34,
);

void main() {
  group('AddLandmarkViewModel address ↔ map binding', () {
    test('a suggestion inside the pin range fills the address and moves the '
        'pin', () async {
      final _FakeLandmarkLogicFacade facade = _FakeLandmarkLogicFacade();
      final _TestAddLandmarkViewModel vm = await _form(facade);

      vm.selectAddressSuggestion(_nearbySuggestion);

      expect(vm.restaurantAddress, _nearbySuggestion.address);
      expect(vm.addressFromMap, isTrue);
      expect(vm.adjustedLocation.isKnown, isTrue);
      expect(vm.locationError, isNull);
      expect(vm.addressPinWarning, isNull);
      vm.dispose();
    });

    test('a suggestion past the pin range keeps the text, warns, and does '
        'not move the pin', () async {
      final _TestAddLandmarkViewModel vm = await _form(
        _FakeLandmarkLogicFacade(),
      );
      const AddressSuggestion suggestion = AddressSuggestion(
        address: 'PV 9, Jalan Genting Kelang, 53300 Kuala Lumpur',
        latitude: 3.16,
        longitude: 101.72,
        distanceMeters: 4400,
      );

      vm.selectAddressSuggestion(suggestion);

      expect(vm.restaurantAddress, suggestion.address);
      expect(vm.adjustedLocation.isKnown, isFalse);
      expect(vm.addressPinWarning, isNotNull);
      expect(vm.addressPinWarning, contains('100 m pin range'));
      expect(vm.addressPinWarning, contains('km'));
      // The picked text is a valid address - the warning never blocks.
      expect(vm.restaurantAddressError, isNull);
      vm.dispose();
    });

    test('recover puts the pin back on the captured spot', () async {
      final _TestAddLandmarkViewModel vm = await _form(
        _FakeLandmarkLogicFacade(),
      );
      vm.selectAddressSuggestion(_nearbySuggestion);
      expect(vm.adjustedLocation.isKnown, isTrue);

      vm.resetLandmarkLocation();

      expect(vm.adjustedLocation.isKnown, isFalse);
      expect(vm.locationError, isNull);
      vm.dispose();
    });

    test(
      'a typed address survives a pin move; the map offers its own back',
      () async {
        final _FakeLandmarkLogicFacade facade = _FakeLandmarkLogicFacade()
          ..reverseAddress =
              'AEON BiG, Jalan Danau Saujana, Setapak, 53000 Kuala Lumpur';
        final _TestAddLandmarkViewModel vm = await _form(facade);
        vm.addListener(() {});

        vm.setRestaurantAddress('12, Jalan Bukit Bintang, 55100 Kuala Lumpur');
        expect(vm.addressFromMap, isFalse);

        vm.adjustLandmarkLocation(_nearby.latitude, _nearby.longitude);
        await _settle();

        // The tourist's words are kept, and the map's version is offered.
        expect(
          vm.restaurantAddress,
          '12, Jalan Bukit Bintang, 55100 Kuala Lumpur',
        );
        expect(vm.canApplyMapAddress, isTrue);
        expect(facade.reverseCalls, isNotEmpty);

        vm.applyMapAddressFromPin();

        expect(vm.restaurantAddress, facade.reverseAddress);
        expect(vm.addressFromMap, isTrue);
        expect(vm.canApplyMapAddress, isFalse);
        vm.dispose();
      },
    );

    test('an empty address is auto-filled from the pinned spot', () async {
      final _FakeLandmarkLogicFacade facade = _FakeLandmarkLogicFacade()
        ..reverseAddress = 'PV 10, Setapak, 53000 Kuala Lumpur';
      final _TestAddLandmarkViewModel vm = await _form(facade);
      vm.addListener(() {});

      vm.prefillAddressFromMap();
      await _settle();

      expect(vm.restaurantAddress, facade.reverseAddress);
      expect(vm.addressFromMap, isTrue);
      expect(facade.reverseCalls.single.latitude, _kl.latitude);
      vm.dispose();
    });

    test('pin moves refresh a map-sourced address automatically', () async {
      final _FakeLandmarkLogicFacade facade = _FakeLandmarkLogicFacade()
        ..reverseAddress =
            'AEON BiG, Jalan Danau Saujana, Setapak, 53000 Kuala Lumpur';
      final _TestAddLandmarkViewModel vm = await _form(facade);
      vm.addListener(() {});
      vm.prefillAddressFromMap();
      await _settle();
      expect(vm.addressFromMap, isTrue);

      facade.reverseAddress = 'PV 10, Setapak, 53000 Kuala Lumpur';
      vm.adjustLandmarkLocation(_nearby.latitude, _nearby.longitude);
      await _settle();

      expect(vm.restaurantAddress, 'PV 10, Setapak, 53000 Kuala Lumpur');
      vm.dispose();
    });

    test(
      'a failed pin lookup shows the notice without touching the field',
      () async {
        final _FakeLandmarkLogicFacade facade = _FakeLandmarkLogicFacade()
          ..reverseAddress = null;
        final _TestAddLandmarkViewModel vm = await _form(facade);
        vm.addListener(() {});

        vm.prefillAddressFromMap();
        await _settle();

        expect(vm.restaurantAddress, isEmpty);
        expect(vm.mapAddressUnavailable, isTrue);
        expect(vm.mapAddressStatus, contains("couldn't find an address"));
        vm.dispose();
      },
    );
  });

  group('AddLandmarkViewModel address suggestions', () {
    test('typing PV lists the facade suggestions', () async {
      final _FakeLandmarkLogicFacade facade = _FakeLandmarkLogicFacade()
        ..searchResults = const <AddressSuggestion>[
          AddressSuggestion(
            address: 'PV 10, Setapak, 53000 Kuala Lumpur',
            latitude: 3.2034,
            longitude: 101.7154,
            distanceMeters: 120,
          ),
          AddressSuggestion(
            address: 'PV18 Residences, Setapak, 53000 Kuala Lumpur',
            latitude: 3.2028,
            longitude: 101.7128,
            distanceMeters: 300,
          ),
        ];
      final _TestAddLandmarkViewModel vm = await _form(facade);
      vm.addListener(() {});

      vm.setRestaurantAddress('PV');
      expect(vm.isSearchingAddress, isFalse); // still inside the debounce
      await _settle();

      expect(facade.searchQueries, contains('PV'));
      expect(vm.addressSuggestions.length, 2);
      expect(vm.addressSearchStatus, isNull);
      vm.dispose();
    });

    test('a failed search shows the unavailable notice', () async {
      final _FakeLandmarkLogicFacade facade = _FakeLandmarkLogicFacade()
        ..searchResults = null;
      final _TestAddLandmarkViewModel vm = await _form(facade);
      vm.addListener(() {});

      vm.setRestaurantAddress('PV');
      await _settle();

      expect(vm.addressSuggestions, isEmpty);
      expect(vm.addressSearchStatus, contains('unavailable'));
      vm.dispose();
    });

    test('no matches shows the empty notice', () async {
      final _FakeLandmarkLogicFacade facade = _FakeLandmarkLogicFacade()
        ..searchResults = const <AddressSuggestion>[];
      final _TestAddLandmarkViewModel vm = await _form(facade);
      vm.addListener(() {});

      vm.setRestaurantAddress('PV');
      await _settle();

      expect(vm.addressSearchStatus, contains('No matching addresses'));
      vm.dispose();
    });

    test('a one-character query never reaches the geocoder', () async {
      final _FakeLandmarkLogicFacade facade = _FakeLandmarkLogicFacade();
      final _TestAddLandmarkViewModel vm = await _form(facade);
      vm.addListener(() {});

      vm.setRestaurantAddress('P');
      await _settle();

      expect(facade.searchQueries, isEmpty);
      vm.dispose();
    });
  });

  group('AddLandmarkViewModel strict address messages', () {
    test('every rule reports the same plain "Invalid address."', () async {
      final _TestAddLandmarkViewModel vm = await _form(
        _FakeLandmarkLogicFacade(),
      );

      // The rules themselves are all still enforced - they just no longer
      // explain themselves to the tourist. Character classes and rule
      // wording are developer talk; "Invalid address." is the message.
      vm.setRestaurantAddress('12, Jln A'); // shorter than the minimum
      expect(vm.restaurantAddressError, 'Invalid address.');

      vm.setRestaurantAddress("12, Jalan O'Brien"); // disallowed character
      expect(vm.restaurantAddressError, 'Invalid address.');

      vm.setRestaurantAddress('#12 Jalan ABC'); // starts with a special
      expect(vm.restaurantAddressError, 'Invalid address.');

      vm.setRestaurantAddress('12,, Jalan ABC'); // repeated special
      expect(vm.restaurantAddressError, 'Invalid address.');

      vm.setRestaurantAddress('Jalan Ampang'); // no house/unit number
      expect(vm.restaurantAddressError, 'Invalid address.');

      vm.setRestaurantAddress('12, Jalan Bukit Bintang, KL');
      expect(vm.restaurantAddressError, isNull);
      vm.dispose();
    });
  });
}
