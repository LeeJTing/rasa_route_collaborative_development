import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/local_food.dart';
import 'package:rasa_route_collaborative_development/domain_model/map.dart';
import 'package:rasa_route_collaborative_development/domain_model/opening_hour.dart';
import 'package:rasa_route_collaborative_development/domain_model/submitted_landmark.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/map_exploration_logic.dart';
import 'package:rasa_route_collaborative_development/model/repositories/discovery_repository_facade.dart';

/// `MapExplorationLogic.pinDetail` used to return landmark pins untouched, so
/// the sheet behind every landmark said "Landmark submitted by a tourist" and
/// "Unknown" even when the place had a category, dish prices and opening
/// hours on record (user report, 2026-09-13).
class _TestMapExplorationLogic extends MapExplorationLogic {
  _TestMapExplorationLogic(this.fake);

  final DiscoveryRepositoryFacade fake;

  @override
  DiscoveryRepositoryFacade createRepository() => fake;
}

class _FakeDiscoveryRepositoryFacade extends DiscoveryRepositoryFacade {
  _FakeDiscoveryRepositoryFacade({
    this.landmarkToReturn,
    this.hoursByPlace = const <String, List<OpeningHour>>{},
  });

  final SubmittedLandmark? landmarkToReturn;
  final Map<String, List<OpeningHour>> hoursByPlace;

  @override
  Future<SubmittedLandmark?> getSubmittedLandmarkById(int landmarkId) async =>
      landmarkToReturn;

  @override
  Future<Map<String, List<OpeningHour>>> openingHoursByPlace({
    Set<String>? placeKeys,
  }) async => hoursByPlace;

  @override
  Future<List<LocalFood>> getLocalFoods() async => const <LocalFood>[];
}

MapPin _landmarkPin() => const MapPin(
  referenceId: '7',
  kind: MapPinKind.landmark,
  latitude: 3.1,
  longitude: 101.6,
  label: 'HOMETOWN ICE KACANG',
  weight: 1,
  distanceMetres: 46,
);

LandmarkItem _dish({
  required int id,
  required String dish,
  double? price,
  double priceMin = 0,
  double priceMax = 0,
  String foodCategory = 'Dessert',
  int localFoodId = 0,
}) => LandmarkItem(
  id: id,
  landmarkId: 7,
  touristId: 'tourist-1',
  localFoodId: localFoodId,
  dish: dish,
  variant: '',
  foodCategory: foodCategory,
  description: '',
  origin: '',
  culturalBackground: '',
  price: price,
  priceMin: priceMin,
  priceMax: priceMax,
  seasonal: '',
  cookingStyle: '',
  mealType: '',
);

SubmittedLandmark _landmark({
  String category = 'Dessert',
  List<LandmarkItem> items = const <LandmarkItem>[],
}) => SubmittedLandmark(
  id: 7,
  name: 'HOMETOWN ICE KACANG',
  latitude: 3.1,
  longitude: 101.6,
  category: category,
  reportedCount: 0,
  status: LandmarkStatus.available,
  items: items,
  openingHours: const <OpeningHour>[],
);

/// A row that is open for the whole of TODAY, whatever day the suite runs on -
/// `_openNow` reads the clock, so a fixed weekday would flake.
OpeningHour _openToday() => OpeningHour(
  id: 1,
  day: Weekday.values[DateTime.now().weekday - 1],
  status: DayStatus.open,
  opensAt: 0,
  closesAt: 1440,
);

void main() {
  test(
    'a landmark comes back with its category, dishes and price range',
    () async {
      final MapExplorationLogic logic = _TestMapExplorationLogic(
        _FakeDiscoveryRepositoryFacade(
          landmarkToReturn: _landmark(
            items: <LandmarkItem>[
              _dish(id: 1, dish: 'Ice Kacang', price: 5),
              _dish(id: 2, dish: 'Cendol', price: 8),
            ],
          ),
          hoursByPlace: <String, List<OpeningHour>>{
            'submittedLandmark:7': <OpeningHour>[_openToday()],
          },
        ),
      );

      final MapPin pin = await logic.pinDetail(_landmarkPin());

      expect(pin.category, 'Dessert restaurant');
      expect(pin.priceRange, 'RM5-8');
      expect(pin.servedFoods, <String>['Ice Kacang', 'Cendol']);
      expect(pin.openNow, isTrue);
      expect(pin.distanceMetres, 46);
    },
  );

  test('one price for every dish reads as that single price', () async {
    final MapExplorationLogic logic = _TestMapExplorationLogic(
      _FakeDiscoveryRepositoryFacade(
        landmarkToReturn: _landmark(
          items: <LandmarkItem>[
            _dish(id: 1, dish: 'Ice Kacang', price: 5),
            _dish(id: 2, dish: 'Cendol', price: 5),
          ],
        ),
      ),
    );

    expect((await logic.pinDetail(_landmarkPin())).priceRange, 'RM5');
  });

  test(
    'a dish with no price falls back to the band it was shown with',
    () async {
      final MapExplorationLogic logic = _TestMapExplorationLogic(
        _FakeDiscoveryRepositoryFacade(
          landmarkToReturn: _landmark(
            items: <LandmarkItem>[
              _dish(id: 1, dish: 'Ice Kacang', priceMin: 4, priceMax: 6),
            ],
          ),
        ),
      );

      expect((await logic.pinDetail(_landmarkPin())).priceRange, 'RM4-6');
    },
  );

  test('the dish category most dishes carry is the one shown', () async {
    final MapExplorationLogic logic = _TestMapExplorationLogic(
      _FakeDiscoveryRepositoryFacade(
        landmarkToReturn: _landmark(
          category: 'Malay',
          items: <LandmarkItem>[
            _dish(
              id: 1,
              dish: 'Wan Tan Mee',
              price: 5,
              foodCategory: 'Chinese',
            ),
            _dish(
              id: 2,
              dish: 'Char Kuey Teow',
              price: 6,
              foodCategory: 'Chinese',
            ),
            _dish(id: 3, dish: 'Nasi Lemak', price: 5, foodCategory: 'Malay'),
          ],
        ),
      ),
    );

    expect(
      (await logic.pinDetail(_landmarkPin())).category,
      'Chinese restaurant',
    );
  });

  test('with no dish category at all the submitted one is used', () async {
    final MapExplorationLogic logic = _TestMapExplorationLogic(
      _FakeDiscoveryRepositoryFacade(
        landmarkToReturn: _landmark(
          category: 'Malay',
          items: <LandmarkItem>[
            _dish(id: 1, dish: 'Ice Kacang', price: 5, foodCategory: ''),
          ],
        ),
      ),
    );

    expect(
      (await logic.pinDetail(_landmarkPin())).category,
      'Malay restaurant',
    );
  });

  test('a landmark with nothing on record leaves the pin alone', () async {
    final MapExplorationLogic logic = _TestMapExplorationLogic(
      _FakeDiscoveryRepositoryFacade(landmarkToReturn: null),
    );

    final MapPin pin = await logic.pinDetail(_landmarkPin());

    expect(pin.category, isNull);
    expect(pin.priceRange, isNull);
    expect(pin.openNow, isNull);
    expect(pin.label, 'HOMETOWN ICE KACANG');
  });
}
