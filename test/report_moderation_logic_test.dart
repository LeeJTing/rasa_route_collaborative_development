import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/opening_hour.dart';
import 'package:rasa_route_collaborative_development/domain_model/report_category.dart';
import 'package:rasa_route_collaborative_development/domain_model/report_claim.dart';
import 'package:rasa_route_collaborative_development/domain_model/restaurant_item.dart';
import 'package:rasa_route_collaborative_development/domain_model/submitted_landmark.dart';
import 'package:rasa_route_collaborative_development/domain_model/tourist_location.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/report_moderation_logic.dart';
import 'package:rasa_route_collaborative_development/model/repositories/auth_repository.dart';
import 'package:rasa_route_collaborative_development/model/repositories/map_repository.dart';
import 'package:rasa_route_collaborative_development/model/repositories/report_repository.dart';
import 'package:rasa_route_collaborative_development/model/repositories/restaurant_repository.dart';
import 'package:rasa_route_collaborative_development/model/repositories/submitted_landmark_repository.dart';

void main() {
  group('submitClaims - sign-in', () {
    test(
      'requires sign-in when no tourist is resolved and writes nothing',
      () async {
        final _FakeReportRepository report = _FakeReportRepository();
        final ReportModerationLogic logic = _build(report, touristId: null);

        final outcome = await logic.submitClaims(
          claims: <ReportClaim>[_addressClaim()],
        );

        expect(outcome.requiresSignIn, isTrue);
        expect(outcome.submittedCount, 0);
        expect(report.inserted, isEmpty);
      },
    );
  });

  group('submitClaims - dedupe', () {
    test('skips claims the tourist already made for the same issue', () async {
      final _FakeReportRepository report = _FakeReportRepository()
        ..already = <String>{_issueKey(_addressClaim())};
      final ReportModerationLogic logic = _build(report, touristId: 't1');

      final outcome = await logic.submitClaims(
        claims: <ReportClaim>[_addressClaim()],
      );

      expect(outcome.alreadyReported, isTrue);
      expect(outcome.submittedCount, 0);
      expect(outcome.duplicateCount, 1);
      expect(report.inserted, isEmpty);
    });
  });

  group('submitClaims - address threshold', () {
    test('below the threshold records the claim but applies nothing', () async {
      final _FakeReportRepository report = _FakeReportRepository()
        ..identicalCount = 4;
      final _FakeRestaurantRepository restaurant = _FakeRestaurantRepository();
      final ReportModerationLogic logic = _build(
        report,
        restaurant: restaurant,
        touristId: 't1',
      );

      final outcome = await logic.submitClaims(
        claims: <ReportClaim>[_addressClaim()],
      );

      expect(outcome.submittedCount, 1);
      expect(outcome.applied, isEmpty);
      expect(report.deletedIdentical, 0);
      expect(restaurant.updatedAddress, isNull);
    });

    test(
      'at the threshold applies the fix and clears the matched rows',
      () async {
        final _FakeReportRepository report = _FakeReportRepository()
          ..identicalCount = 5
          // Three on-site pins, all inside 30 m of each other.
          ..issuePins = <TouristLocation>[_pin(0), _pin(10), _pin(20)];
        final _FakeRestaurantRepository restaurant =
            _FakeRestaurantRepository();
        final ReportModerationLogic logic = _build(
          report,
          restaurant: restaurant,
          touristId: 't1',
        );

        final outcome = await logic.submitClaims(
          claims: <ReportClaim>[_addressClaim()],
        );

        expect(outcome.submittedCount, 1);
        expect(outcome.applied, <String>['Address updated']);
        expect(restaurant.updatedAddress, '12 Jalan Merdeka');
        expect(report.deletedIdentical, 1);
      },
    );

    test('the applied spot is the median of the pins that agree', () async {
      // The reported text is the OpenStreetMap wording for the spot, which is
      // approximate - so the coordinates come from the VALID pins, and only
      // from those that agree with each other (user's design, 2026-09-13).
      final _FakeReportRepository report = _FakeReportRepository()
        ..identicalCount = 5
        ..issuePins = <TouristLocation>[
          _pin(0),
          _pin(10),
          _pin(20),
          // A dissenting tourist 500 m away must not drag the result.
          _pin(500),
        ];
      final _FakeRestaurantRepository restaurant = _FakeRestaurantRepository();
      final ReportModerationLogic logic = _build(
        report,
        restaurant: restaurant,
        touristId: 't1',
      );

      await logic.submitClaims(claims: <ReportClaim>[_addressClaim()]);

      expect(restaurant.updatedAddress, '12 Jalan Merdeka');
      expect(restaurant.updatedAddressLatitude, closeTo(_latitudeAt(10), 1e-9));
      expect(restaurant.updatedAddressLongitude, closeTo(101.69, 1e-9));
    });

    test('the fix is held back while the pins disagree', () async {
      final _FakeReportRepository report = _FakeReportRepository()
        ..identicalCount = 5
        // Only two close together - not a consensus.
        ..issuePins = <TouristLocation>[_pin(0), _pin(8), _pin(600)];
      final _FakeRestaurantRepository restaurant = _FakeRestaurantRepository();
      final ReportModerationLogic logic = _build(
        report,
        restaurant: restaurant,
        touristId: 't1',
      );

      final outcome = await logic.submitClaims(
        claims: <ReportClaim>[_addressClaim()],
      );

      expect(outcome.submittedCount, 1);
      expect(outcome.applied, isEmpty);
      expect(restaurant.updatedAddress, isNull);
      // The rows are KEPT, so the next valid report re-runs the check.
      expect(report.deletedIdentical, 0);
    });

    test('with no pins at all the fix is held back too', () async {
      final _FakeReportRepository report = _FakeReportRepository()
        ..identicalCount = 5;
      final _FakeRestaurantRepository restaurant = _FakeRestaurantRepository();
      final ReportModerationLogic logic = _build(
        report,
        restaurant: restaurant,
        touristId: 't1',
      );

      await logic.submitClaims(claims: <ReportClaim>[_addressClaim()]);

      expect(restaurant.updatedAddress, isNull);
      expect(report.deletedIdentical, 0);
    });
  });

  group('submitClaims - item price', () {
    test('updates the right place-kind item price at the threshold', () async {
      final _FakeReportRepository report = _FakeReportRepository()
        ..identicalCount = 5;
      final _FakeRestaurantRepository restaurant = _FakeRestaurantRepository();
      final ReportModerationLogic logic = _build(
        report,
        restaurant: restaurant,
        touristId: 't1',
      );

      final outcome = await logic.submitClaims(
        claims: <ReportClaim>[
          ReportClaim(
            placeKind: ReportPlaceKind.restaurant,
            placeId: 1,
            category: ReportCategory.itemPrice,
            itemKind: ReportItemKind.restaurantItem,
            itemId: 11,
            payload: 'price:8.50',
          ),
        ],
      );

      expect(outcome.applied, <String>['Price updated']);
      expect(restaurant.updatedPriceItemId, 11);
      expect(restaurant.updatedPrice, 8.5);
    });

    test('updates landmark items through the landmark repo', () async {
      final _FakeReportRepository report = _FakeReportRepository()
        ..identicalCount = 5;
      final _FakeLandmarkRepository landmark = _FakeLandmarkRepository();
      final ReportModerationLogic logic = _build(
        report,
        landmark: landmark,
        touristId: 't1',
      );

      final outcome = await logic.submitClaims(
        claims: <ReportClaim>[
          ReportClaim(
            placeKind: ReportPlaceKind.landmark,
            placeId: 2,
            category: ReportCategory.itemPrice,
            itemKind: ReportItemKind.landmarkItem,
            itemId: 22,
            payload: 'price:6.00',
          ),
        ],
      );

      expect(outcome.applied, <String>['Price updated']);
      expect(landmark.updatedPriceItemId, 22);
      expect(landmark.updatedPrice, 6.0);
    });
  });

  group('submitClaims - item not exist', () {
    test('soft-removes the item when more items remain', () async {
      final _FakeReportRepository report = _FakeReportRepository()
        ..identicalCount = 5;
      final _FakeLandmarkRepository landmark = _FakeLandmarkRepository()
        ..visibleCount = 2;
      final ReportModerationLogic logic = _build(
        report,
        landmark: landmark,
        touristId: 't1',
      );

      final outcome = await logic.submitClaims(
        claims: <ReportClaim>[
          ReportClaim(
            placeKind: ReportPlaceKind.landmark,
            placeId: 2,
            category: ReportCategory.itemNotExist,
            itemKind: ReportItemKind.landmarkItem,
            itemId: 22,
            payload: 'not-exist',
          ),
        ],
      );

      expect(outcome.applied, <String>['Item removed from menu']);
      expect(outcome.placeHiddenNow, isFalse);
      expect(landmark.removedItemIds, <int>[22]);
      expect(landmark.removedLandmarks, isEmpty);
      // Price/not-exist claims for the removed item are cleared too.
      expect(report.deletedIssues, 1);
    });

    test('hides the whole place when no visible items remain', () async {
      final _FakeReportRepository report = _FakeReportRepository()
        ..identicalCount = 5;
      final _FakeLandmarkRepository landmark = _FakeLandmarkRepository()
        ..visibleCount = 0;
      final ReportModerationLogic logic = _build(
        report,
        landmark: landmark,
        touristId: 't1',
      );

      final outcome = await logic.submitClaims(
        claims: <ReportClaim>[
          ReportClaim(
            placeKind: ReportPlaceKind.landmark,
            placeId: 2,
            category: ReportCategory.itemNotExist,
            itemKind: ReportItemKind.landmarkItem,
            itemId: 22,
            payload: 'not-exist',
          ),
        ],
      );

      expect(outcome.applied.single, contains('no items left'));
      expect(outcome.placeHiddenNow, isTrue);
      expect(landmark.removedLandmarks, <int>[2]);
    });
  });

  group('submitClaims - closures', () {
    test('permanent closure hides the place at the threshold', () async {
      final _FakeReportRepository report = _FakeReportRepository()
        ..identicalCount = 10;
      final _FakeRestaurantRepository restaurant = _FakeRestaurantRepository();
      final ReportModerationLogic logic = _build(
        report,
        restaurant: restaurant,
        touristId: 't1',
      );

      final outcome = await logic.submitClaims(
        claims: <ReportClaim>[
          ReportClaim(
            placeKind: ReportPlaceKind.restaurant,
            placeId: 1,
            category: ReportCategory.closedPermanently,
            payload: 'closed-permanently',
          ),
        ],
      );

      expect(outcome.applied.single, contains('closed permanently'));
      expect(outcome.placeHiddenNow, isTrue);
      expect(restaurant.frozenWithoutUntil, <int>[1]);
    });

    test('temporary closure counts ACROSS durations and records the '
        'most-voted END DATE when 10 are in', () async {
      final _FakeReportRepository report = _FakeReportRepository()
        ..issueCount = 10
        ..issueClaims = <ClosureClaim>[
          // 7 reported 3 days vs 3 reported 7 days, all filed today -> the
          // end dates are today+3 and today+7; today+3 wins 7 votes to 3.
          for (int i = 0; i < 7; i++)
            _closureClaim(
              const ProposedClosure(amount: 3, unit: ClosureUnit.days),
            ),
          for (int i = 0; i < 3; i++)
            _closureClaim(
              const ProposedClosure(amount: 7, unit: ClosureUnit.days),
            ),
        ];
      final _FakeLandmarkRepository landmark = _FakeLandmarkRepository();
      final ReportModerationLogic logic = _build(
        report,
        landmark: landmark,
        touristId: 't1',
      );

      final outcome = await logic.submitClaims(
        claims: <ReportClaim>[
          ReportClaim(
            placeKind: ReportPlaceKind.landmark,
            placeId: 2,
            category: ReportCategory.closedTemporarily,
            payload: _closurePayload(
              const ProposedClosure(amount: 3, unit: ClosureUnit.days),
            ),
          ),
        ],
      );

      expect(outcome.applied.single, contains('closed temporarily'));
      expect(outcome.placeHiddenNow, isTrue);
      expect(landmark.frozenWithUntil, hasLength(1));
      // The 3-day end date got 7 votes vs the 7-day date's 3 -> ~3 days out.
      final DateTime closedUntil = landmark.frozenWithUntil.single.$2!;
      expect(
        closedUntil.isBefore(DateTime.now().add(const Duration(days: 4))),
        isTrue,
      );
      // The whole issue is cleared (all durations contributed).
      expect(report.deletedIssues, 1);
    });

    test('temporary closure tie breaks to the LATER end date', () async {
      final _FakeReportRepository report = _FakeReportRepository()
        ..issueCount = 10
        ..issueClaims = <ClosureClaim>[
          for (int i = 0; i < 5; i++)
            _closureClaim(
              const ProposedClosure(amount: 2, unit: ClosureUnit.days),
            ),
          for (int i = 0; i < 5; i++)
            _closureClaim(
              const ProposedClosure(amount: 9, unit: ClosureUnit.days),
            ),
        ];
      final _FakeRestaurantRepository restaurant = _FakeRestaurantRepository();
      final ReportModerationLogic logic = _build(
        report,
        restaurant: restaurant,
        touristId: 't1',
      );

      await logic.submitClaims(
        claims: <ReportClaim>[
          ReportClaim(
            placeKind: ReportPlaceKind.restaurant,
            placeId: 1,
            category: ReportCategory.closedTemporarily,
            payload: _closurePayload(
              const ProposedClosure(amount: 2, unit: ClosureUnit.days),
            ),
          ),
        ],
      );

      final DateTime closedUntil = restaurant.frozenWithUntil.single.$2!;
      expect(
        closedUntil.isAfter(DateTime.now().add(const Duration(days: 8))),
        isTrue,
      );
    });
  });

  group('submitClaims - hours', () {
    test('replaces only the claimed day at the threshold', () async {
      final _FakeReportRepository report = _FakeReportRepository()
        ..identicalCount = 10;
      final _FakeRestaurantRepository restaurant = _FakeRestaurantRepository();
      final ReportModerationLogic logic = _build(
        report,
        restaurant: restaurant,
        touristId: 't1',
      );

      final outcome = await logic.submitClaims(
        claims: <ReportClaim>[
          ReportClaim(
            placeKind: ReportPlaceKind.restaurant,
            placeId: 1,
            category: ReportCategory.operatingHours,
            day: Weekday.monday,
            payload: 'hours:open:540:900',
          ),
        ],
      );

      expect(outcome.applied, <String>['Monday hours updated']);
      expect(restaurant.replacedDays, <Weekday>[Weekday.monday]);
      expect(restaurant.replacedRows.single, hasLength(1));
      expect(restaurant.replacedRows.single.single.status, DayStatus.open);
      expect(restaurant.replacedRows.single.single.opensAt, 540);
    });
  });

  group('reportableItemsFor', () {
    test('maps restaurant menu rows without removed items', () async {
      final _FakeRestaurantRepository restaurant = _FakeRestaurantRepository()
        ..reportable = <RestaurantItem>[
          const RestaurantItem(
            id: 11,
            restaurantId: 1,
            localFoodId: 1,
            foodName: 'Nasi Lemak',
            price: 8,
            currency: 'RM',
            foodCategory: 'Rice',
          ),
        ];
      final ReportModerationLogic logic = _build(
        _FakeReportRepository(),
        restaurant: restaurant,
      );

      final List<ReportableMenuItem> items = await logic.reportableItemsFor(
        placeKind: ReportPlaceKind.restaurant,
        placeId: 1,
      );

      expect(items.single.itemKind, ReportItemKind.restaurantItem);
      expect(items.single.name, 'Nasi Lemak');
      expect(items.single.price, 8);
    });

    test('maps landmark dishes through the landmark repo', () async {
      final _FakeLandmarkRepository landmark = _FakeLandmarkRepository()
        ..reportable = <LandmarkItem>[_landmarkItem(22, 'Laksa')];
      final ReportModerationLogic logic = _build(
        _FakeReportRepository(),
        landmark: landmark,
      );

      final List<ReportableMenuItem> items = await logic.reportableItemsFor(
        placeKind: ReportPlaceKind.landmark,
        placeId: 2,
      );

      expect(items.single.itemKind, ReportItemKind.landmarkItem);
      expect(items.single.name, 'Laksa');
    });
  });
}

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

ReportClaim _addressClaim({double? latitude, double? longitude}) => ReportClaim(
  placeKind: ReportPlaceKind.restaurant,
  placeId: 1,
  category: ReportCategory.address,
  latitude: latitude,
  longitude: longitude,
  payload: 'address:12 Jalan Merdeka',
);

/// A pin [northMetres] north of the reported spot. One degree of latitude is
/// ~111.32 km, so the offsets in these tests read as metres.
double _latitudeAt(double northMetres) => 3.139 + northMetres / 111320;

TouristLocation _pin(double northMetres) =>
    TouristLocation(latitude: _latitudeAt(northMetres), longitude: 101.69);

String _closurePayload(ProposedClosure closure) =>
    'closed-temporarily:${closure.amount}:${closure.unit.columnValue}';

/// A stored closure claim stamped [createdAt] (default now - the tests that
/// care about END DATES pass their own).
ClosureClaim _closureClaim(ProposedClosure closure, {DateTime? createdAt}) =>
    ClosureClaim(
      payload: _closurePayload(closure),
      createdAt: createdAt ?? DateTime.now(),
    );

String _issueKey(ReportClaim claim) =>
    '${claim.placeKind.columnValue}:${claim.placeId}:'
    '${claim.category.name}:${claim.itemKind?.columnValue ?? '-'}:'
    '${claim.itemId ?? '-'}:${claim.day?.name ?? '-'}';

LandmarkItem _landmarkItem(int id, String dish) => LandmarkItem(
  id: id,
  landmarkId: 2,
  touristId: 't1',
  dish: dish,
  variant: '',
  foodCategory: 'Noodles',
  description: '',
  origin: '',
  culturalBackground: '',
  seasonal: 'All Year',
  cookingStyle: '',
  mealType: 'All Day',
);

ReportModerationLogic _build(
  _FakeReportRepository report, {
  _FakeRestaurantRepository? restaurant,
  _FakeLandmarkRepository? landmark,
  String? touristId = 't1',
}) => _TestReportModerationLogic(
  report,
  restaurant ?? _FakeRestaurantRepository(),
  landmark ?? _FakeLandmarkRepository(),
  _FakeAuthRepository(touristId),
  _FakeMapRepository(),
);

class _TestReportModerationLogic extends ReportModerationLogic {
  _TestReportModerationLogic(
    this.fakeReport,
    this.fakeRestaurant,
    this.fakeLandmark,
    this.fakeAuth,
    this.fakeMap,
  );

  final _FakeReportRepository fakeReport;
  final _FakeRestaurantRepository fakeRestaurant;
  final _FakeLandmarkRepository fakeLandmark;
  final _FakeAuthRepository fakeAuth;
  final _FakeMapRepository fakeMap;

  @override
  ReportRepository createReportRepository() => fakeReport;

  @override
  RestaurantRepository createRestaurantRepository() => fakeRestaurant;

  @override
  SubmittedLandmarkRepository createLandmarkRepository() => fakeLandmark;

  @override
  AuthRepository createAuthRepository() => fakeAuth;

  @override
  MapRepository createMapRepository() => fakeMap;
}

class _FakeReportRepository extends ReportRepository {
  int identicalCount = 0;
  int issueCount = 0;
  List<ClosureClaim> issueClaims = const <ClosureClaim>[];
  List<TouristLocation> issuePins = const <TouristLocation>[];
  Set<String> already = <String>{};
  final List<Map<String, Object?>> inserted = <Map<String, Object?>>[];
  int deletedIdentical = 0;
  int deletedIssues = 0;

  @override
  Future<bool> alreadyReported({
    required ReportClaim claim,
    required String touristId,
  }) async => already.contains(_issueKey(claim));

  @override
  Future<void> insertClaim({
    required ReportClaim claim,
    String? touristId,
  }) async {
    inserted.add(<String, Object?>{'claim': claim, 'tourist': touristId});
  }

  @override
  Future<int> countIdentical(ReportClaim claim) async => identicalCount;

  @override
  Future<int> countIssue(ReportClaim claim) async => issueCount;

  @override
  Future<List<ClosureClaim>> closureClaimsForIssue(ReportClaim claim) async =>
      issueClaims;

  @override
  Future<List<TouristLocation>> locationsForIssue(ReportClaim claim) async =>
      issuePins;

  @override
  Future<void> deleteIdentical(ReportClaim claim) async {
    deletedIdentical++;
  }

  @override
  Future<void> deleteIssue(ReportClaim claim) async {
    deletedIssues++;
  }
}

class _FakeRestaurantRepository extends RestaurantRepository {
  List<RestaurantItem> reportable = const <RestaurantItem>[];
  String? updatedAddress;
  double? updatedAddressLatitude;
  double? updatedAddressLongitude;
  int? updatedPriceItemId;
  double? updatedPrice;
  List<int> frozenWithoutUntil = <int>[];
  final List<(int, DateTime?)> frozenWithUntil = <(int, DateTime?)>[];
  final List<Weekday> replacedDays = <Weekday>[];
  final List<List<OpeningHour>> replacedRows = <List<OpeningHour>>[];

  @override
  Future<List<RestaurantItem>> getReportableItems(int restaurantId) async =>
      reportable;

  @override
  Future<void> updateRestaurantItemPrice(int itemId, double price) async {
    updatedPriceItemId = itemId;
    updatedPrice = price;
  }

  @override
  Future<void> updateRestaurantAddress(
    int restaurantId,
    String address, {
    double? latitude,
    double? longitude,
  }) async {
    updatedAddress = address;
    updatedAddressLatitude = latitude;
    updatedAddressLongitude = longitude;
  }

  @override
  Future<void> freezeRestaurant(
    int restaurantId, {
    DateTime? closedUntil,
  }) async {
    if (closedUntil == null) {
      frozenWithoutUntil.add(restaurantId);
    } else {
      frozenWithUntil.add((restaurantId, closedUntil));
    }
  }

  @override
  Future<void> replaceRestaurantOpeningHourDay(
    int restaurantId,
    Weekday day,
    List<OpeningHour> rows,
  ) async {
    replacedDays.add(day);
    replacedRows.add(rows);
  }
}

class _FakeLandmarkRepository extends SubmittedLandmarkRepository {
  List<LandmarkItem> reportable = const <LandmarkItem>[];
  List<int> removedItemIds = <int>[];
  List<int> removedLandmarks = <int>[];
  int visibleCount = 0;
  int? updatedPriceItemId;
  double? updatedPrice;
  List<int> frozenWithoutUntil = <int>[];
  final List<(int, DateTime?)> frozenWithUntil = <(int, DateTime?)>[];

  @override
  Future<List<LandmarkItem>> getReportableItems(int landmarkId) async =>
      reportable;

  @override
  Future<void> updateLandmarkItemPrice(int itemId, double price) async {
    updatedPriceItemId = itemId;
    updatedPrice = price;
  }

  @override
  Future<void> softRemoveLandmarkItem(int itemId) async {
    removedItemIds.add(itemId);
  }

  @override
  Future<int> countVisibleLandmarkItems(int landmarkId) async => visibleCount;

  @override
  Future<void> removeLandmark(int landmarkId) async {
    removedLandmarks.add(landmarkId);
  }

  @override
  Future<void> freezeLandmark(int landmarkId, {DateTime? closedUntil}) async {
    if (closedUntil == null) {
      frozenWithoutUntil.add(landmarkId);
    } else {
      frozenWithUntil.add((landmarkId, closedUntil));
    }
  }
}

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository(this.result);

  final String? result;

  @override
  Future<String?> currentTouristId() async => result;
}

class _FakeMapRepository extends MapRepository {
  int clearCount = 0;

  @override
  void clearCache() {
    clearCount++;
  }
}
