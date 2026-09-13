import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/address_suggestion.dart';
import 'package:rasa_route_collaborative_development/domain_model/opening_hour.dart';
import 'package:rasa_route_collaborative_development/domain_model/report_category.dart';
import 'package:rasa_route_collaborative_development/domain_model/report_claim.dart';
import 'package:rasa_route_collaborative_development/domain_model/report_outcome.dart';
import 'package:rasa_route_collaborative_development/domain_model/tourist_location.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/report_logic_facade.dart';
import 'package:rasa_route_collaborative_development/view_models/current_location_facade.dart';
import 'package:rasa_route_collaborative_development/view_models/report_place_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ReportPlaceViewModel build(
    _FakeReportLogicFacade logic, {
    ReportPlaceKind kind = ReportPlaceKind.restaurant,
    int placeId = 1,
    String name = 'OldTown',
    TouristLocation location = TouristLocation.unknown,
  }) {
    final ReportPlaceViewModel viewModel = _TestReportPlaceViewModel(logic);
    viewModel.configure(kind, placeId, name, location);
    return viewModel;
  }

  group('configure / lifecycle', () {
    test('configure stores the place from the handoff', () {
      final ReportPlaceViewModel viewModel = build(_FakeReportLogicFacade());
      expect(viewModel.placeKind, ReportPlaceKind.restaurant);
      expect(viewModel.placeName, 'OldTown');
      expect(viewModel.isConfigured, isTrue);
      viewModel.dispose();
    });

    test('onInit errors when never configured', () async {
      final ReportPlaceViewModel viewModel = _TestReportPlaceViewModel(
        _FakeReportLogicFacade(),
      );
      await viewModel.onInit();
      expect(viewModel.hasError, isTrue);
      viewModel.dispose();
    });
  });

  group('category selection', () {
    test('selecting an item category loads the menu items', () async {
      final _FakeReportLogicFacade logic = _FakeReportLogicFacade()
        ..menuItems = <ReportableMenuItem>[
          const ReportableMenuItem(
            itemKind: ReportItemKind.restaurantItem,
            id: 11,
            name: 'Nasi Lemak',
            price: 8,
          ),
        ];
      final ReportPlaceViewModel viewModel = build(logic);
      viewModel.selectCategory(ReportCategory.itemPrice);
      // Let the fire-and-forget _loadItems settle.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.items, hasLength(1));
      expect(viewModel.items.single.name, 'Nasi Lemak');
      viewModel.dispose();
    });
  });

  group('hours editing', () {
    test(
      'setDayStatus flips a day to Open and setRangeTime fills its hours',
      () {
        final ReportPlaceViewModel viewModel = build(_FakeReportLogicFacade());
        viewModel.setDayStatus(Weekday.monday, DayStatus.open);
        expect(viewModel.hasHoursCorrection, isTrue);

        viewModel.setRangeTime(Weekday.monday, 0, true, 540);
        viewModel.setRangeTime(Weekday.monday, 0, false, 900);
        expect(viewModel.hours[Weekday.monday]!.single.opensAt, 540);
        expect(viewModel.hours[Weekday.monday]!.single.closesAt, 900);
        viewModel.dispose();
      },
    );

    test('an overnight close is encoded as next-day minutes (+1440)', () {
      final ReportPlaceViewModel viewModel = build(_FakeReportLogicFacade());
      viewModel.setDayStatus(Weekday.monday, DayStatus.open);
      viewModel.setRangeTime(Weekday.monday, 0, true, 22 * 60);
      viewModel.setRangeTime(Weekday.monday, 0, false, 2 * 60);
      expect(viewModel.hours[Weekday.monday]!.single.opensAt, 22 * 60);
      expect(viewModel.hours[Weekday.monday]!.single.closesAt, 26 * 60);
      viewModel.dispose();
    });

    test('hasHoursCorrection is false while every day stays Unknown', () {
      final ReportPlaceViewModel viewModel = build(_FakeReportLogicFacade());
      expect(viewModel.hasHoursCorrection, isFalse);
      viewModel.dispose();
    });
  });

  group('submit - building claims', () {
    test('hours report submits one claim per corrected day', () async {
      final _FakeReportLogicFacade logic = _FakeReportLogicFacade()
        ..outcome = const ReportSubmitOutcome(submittedCount: 2);
      final ReportPlaceViewModel viewModel = build(logic);
      viewModel.selectCategory(ReportCategory.operatingHours);

      viewModel.setDayStatus(Weekday.monday, DayStatus.open);
      viewModel.setRangeTime(Weekday.monday, 0, true, 540);
      viewModel.setRangeTime(Weekday.monday, 0, false, 900);
      viewModel.setDayStatus(Weekday.tuesday, DayStatus.closed);
      await viewModel.submit();

      expect(logic.submittedClaims, hasLength(2));
      expect(
        logic.submittedClaims.every(
          (ReportClaim claim) =>
              claim.category == ReportCategory.operatingHours &&
              claim.placeKind == ReportPlaceKind.restaurant &&
              claim.placeId == 1,
        ),
        isTrue,
      );
      expect(viewModel.reportSubmitted, isTrue);
      viewModel.dispose();
    });

    test('item price report requires an item and a numeric price', () async {
      final _FakeReportLogicFacade logic = _FakeReportLogicFacade()
        ..outcome = const ReportSubmitOutcome(submittedCount: 1);
      final ReportPlaceViewModel viewModel = build(logic);
      viewModel.selectCategory(ReportCategory.itemPrice);
      await Future<void>.delayed(Duration.zero);

      // No item selected yet -> nothing submitted, form error.
      viewModel.setPriceText('8.50');
      await viewModel.submit();
      expect(logic.submittedClaims, isEmpty);
      expect(viewModel.formError, isNotNull);
      expect(viewModel.itemError, isNotNull);

      viewModel.selectItem(
        const ReportableMenuItem(
          itemKind: ReportItemKind.restaurantItem,
          id: 11,
          name: 'Nasi Lemak',
          price: 8,
        ),
      );
      await viewModel.submit();

      expect(logic.submittedClaims, hasLength(1));
      expect(logic.submittedClaims.single.category, ReportCategory.itemPrice);
      expect(logic.submittedClaims.single.itemId, 11);
      expect(logic.submittedClaims.single.payload, 'price:8.50');
      viewModel.dispose();
    });

    test('address report uses trimmed text', () async {
      final _FakeReportLogicFacade logic = _FakeReportLogicFacade()
        ..outcome = const ReportSubmitOutcome(submittedCount: 1);
      final ReportPlaceViewModel viewModel = build(logic);
      viewModel.selectCategory(ReportCategory.address);
      viewModel.setAddressText('  12 Jalan Merdeka  ');
      await viewModel.submit();

      expect(logic.submittedClaims.single.payload, 'address:12 Jalan Merdeka');
      viewModel.dispose();
    });

    test('temporary closure report requires a positive duration', () async {
      final _FakeReportLogicFacade logic = _FakeReportLogicFacade()
        ..outcome = const ReportSubmitOutcome(submittedCount: 1);
      final ReportPlaceViewModel viewModel = build(logic);
      viewModel.selectCategory(ReportCategory.closedTemporarily);
      viewModel.setClosureAmountText('0');
      await viewModel.submit();
      expect(logic.submittedClaims, isEmpty);
      expect(viewModel.formError, isNotNull);
      expect(viewModel.closureError, isNotNull);

      viewModel.setClosureAmountText('3');
      viewModel.setClosureUnit(ClosureUnit.days);
      await viewModel.submit();
      expect(logic.submittedClaims.single.payload, 'closed-temporarily:3:days');
      viewModel.dispose();
    });

    test(
      'invalid address and incomplete hours stay out of the repository',
      () async {
        final _FakeReportLogicFacade logic = _FakeReportLogicFacade();
        final ReportPlaceViewModel viewModel = build(logic);

        viewModel.selectCategory(ReportCategory.address);
        viewModel.setAddressText('---');
        await viewModel.submit();
        expect(viewModel.addressError, isNotNull);
        expect(logic.submittedClaims, isEmpty);

        viewModel.selectCategory(ReportCategory.operatingHours);
        viewModel.setDayStatus(Weekday.monday, DayStatus.open);
        await viewModel.submit();
        expect(viewModel.hoursError, isNotNull);
        expect(logic.submittedClaims, isEmpty);
        viewModel.dispose();
      },
    );
  });

  group('submit - outcome handling', () {
    test('requiresSignIn surfaces without writing', () async {
      final _FakeReportLogicFacade logic = _FakeReportLogicFacade()
        ..outcome = const ReportSubmitOutcome(requiresSignIn: true);
      final ReportPlaceViewModel viewModel = build(logic);
      viewModel.selectCategory(ReportCategory.closedPermanently);
      await viewModel.submit();

      expect(viewModel.requiresSignIn, isTrue);
      expect(viewModel.reportSubmitted, isFalse);
      viewModel.dispose();
    });

    test('alreadyReported surfaces when every claim was a duplicate', () async {
      final _FakeReportLogicFacade logic = _FakeReportLogicFacade()
        ..outcome = const ReportSubmitOutcome(
          alreadyReported: true,
          submittedCount: 0,
        );
      final ReportPlaceViewModel viewModel = build(logic);
      viewModel.selectCategory(ReportCategory.closedPermanently);
      await viewModel.submit();

      expect(viewModel.alreadyReported, isTrue);
      viewModel.dispose();
    });

    test('placeHiddenNow flags the hidden place without throwing', () async {
      final _FakeReportLogicFacade logic = _FakeReportLogicFacade()
        ..outcome = const ReportSubmitOutcome(
          submittedCount: 1,
          placeHiddenNow: true,
          applied: <String>['Place hidden (closed permanently)'],
        );
      final ReportPlaceViewModel viewModel = build(logic);

      viewModel.selectCategory(ReportCategory.closedPermanently);
      // The own-map-data-changed broadcast is swallowed safely in a bare test
      // (no dashboard registered) - submitting must not throw.
      await viewModel.submit();

      expect(viewModel.placeHiddenNow, isTrue);
      expect(viewModel.appliedMessage, contains('closed permanently'));
      viewModel.dispose();
    });

    test(
      'consumeOutcome resets the transient flags for a second report',
      () async {
        final _FakeReportLogicFacade logic = _FakeReportLogicFacade()
          ..outcome = const ReportSubmitOutcome(
            submittedCount: 1,
            placeHiddenNow: true,
            applied: <String>['Address updated'],
          );
        final ReportPlaceViewModel viewModel = build(logic);
        viewModel.selectCategory(ReportCategory.address);
        viewModel.setAddressText('12, Jalan Merdeka, Kuala Lumpur');
        await viewModel.submit();
        expect(viewModel.appliedMessage, isNotEmpty);

        viewModel.consumeOutcome();
        expect(viewModel.reportSubmitted, isFalse);
        expect(viewModel.placeHiddenNow, isFalse);
        expect(viewModel.appliedMessage, isEmpty);
        viewModel.dispose();
      },
    );
  });

  // The address report works like the Add-Landmark form's address field: a
  // map pin, OpenStreetMap suggestions, and the pin's own composed address
  // (user request, 2026-09-13). These tests drive the ViewModel directly -
  // no widget, no network (the facade is faked).
  group('address report map binding', () {
    const TouristLocation place = TouristLocation(
      latitude: 3.1,
      longitude: 101.6,
    );

    test('the pin starts on the place the app already has', () {
      final ReportPlaceViewModel viewModel = build(
        _FakeReportLogicFacade(),
        location: place,
      );

      expect(viewModel.reportLocation.latitude, 3.1);
      expect(viewModel.reportLocation.longitude, 101.6);
      viewModel.dispose();
    });

    test('moving the pin fills an empty address field from the map', () async {
      final _FakeReportLogicFacade logic = _FakeReportLogicFacade();
      final ReportPlaceViewModel viewModel = build(logic, location: place);
      // A watched ViewModel counts as "a page is open" - the lookup only runs
      // then, exactly like the Add-Landmark form.
      viewModel.addListener(() {});

      viewModel.moveReportLocation(3.2, 101.7);

      await Future<void>.delayed(
        ReportPlaceViewModel.mapAddressLookupDelay +
            const Duration(milliseconds: 250),
      );

      expect(viewModel.reportLocation.latitude, 3.2);
      expect(viewModel.addressText, '10, Jalan Foo, 50000 Kuala Lumpur');
      expect(viewModel.addressError, isNull);
      expect(viewModel.mapAddressStatus, isNull);
      viewModel.dispose();
    });

    test("the 150 cap and warn zone are the Add-Landmark form's", () {
      final ReportPlaceViewModel viewModel = build(_FakeReportLogicFacade());
      viewModel.selectCategory(ReportCategory.address);

      expect(viewModel.addressMaxLength, 150);

      // 149 characters - the last acceptable length; the amber nudge shows.
      viewModel.setAddressText('12, Jalan A'.padRight(149, 'A'));
      expect(viewModel.addressError, isNull);
      expect(
        viewModel.addressWarning,
        'Address should stay under 150 characters (currently 149).',
      );

      // 150 - the form's hard stop, word for word.
      viewModel.setAddressText('12, Jalan A'.padRight(150, 'A'));
      expect(viewModel.addressError, 'Address is too long.');
      expect(viewModel.addressWarning, isNull);
      viewModel.dispose();
    });

    test('typed text is kept, and the map wording is offered back', () async {
      final _FakeReportLogicFacade logic = _FakeReportLogicFacade();
      final ReportPlaceViewModel viewModel = build(logic, location: place);
      viewModel.addListener(() {});
      viewModel.selectCategory(ReportCategory.address);
      viewModel.setAddressText('12, Jalan Bukit Bintang, Kuala Lumpur');

      viewModel.moveReportLocation(3.2, 101.7);
      await Future<void>.delayed(
        ReportPlaceViewModel.mapAddressLookupDelay +
            const Duration(milliseconds: 250),
      );

      // Their wording survives the pin move ...
      expect(viewModel.addressText, '12, Jalan Bukit Bintang, Kuala Lumpur');
      // ... and the map's version is one tap away.
      expect(viewModel.canApplyMapAddress, isTrue);

      viewModel.applyMapAddressFromPin();
      expect(viewModel.addressText, '10, Jalan Foo, 50000 Kuala Lumpur');
      expect(viewModel.canApplyMapAddress, isFalse);
      viewModel.dispose();
    });

    test('a suggestion fills the field and moves the pin to it', () {
      final ReportPlaceViewModel viewModel = build(
        _FakeReportLogicFacade(),
        location: place,
      );
      viewModel.selectCategory(ReportCategory.address);

      viewModel.selectAddressSuggestion(
        const AddressSuggestion(
          address: '20, Jalan Sultan, 50000 Kuala Lumpur',
          latitude: 3.14,
          longitude: 101.69,
        ),
      );

      expect(viewModel.addressText, '20, Jalan Sultan, 50000 Kuala Lumpur');
      expect(viewModel.reportLocation.latitude, 3.14);
      expect(viewModel.reportLocation.longitude, 101.69);
      expect(viewModel.addressSuggestions, isEmpty);
      viewModel.dispose();
    });

    test('with no location from the handoff there is no map to open', () {
      final ReportPlaceViewModel viewModel = build(_FakeReportLogicFacade());

      expect(viewModel.reportLocation.isKnown, isFalse);
      expect(viewModel.mapAddressStatus, isNull);
      viewModel.dispose();
    });

    test('the submitted claim carries the pinned spot', () async {
      // The address text is whatever the tourist ended up with (usually the
      // OpenStreetMap wording); the pin is the exact part, so it rides the
      // claim (user request, 2026-09-13).
      final _FakeReportLogicFacade logic = _FakeReportLogicFacade();
      final ReportPlaceViewModel viewModel = build(logic, location: place);
      viewModel.selectCategory(ReportCategory.address);
      viewModel.setAddressText('12, Jalan Bukit Bintang, Kuala Lumpur');
      viewModel.moveReportLocation(3.14, 101.69);

      await viewModel.submit();

      final ReportClaim claim = logic.submittedClaims.single;
      expect(claim.payload, 'address:12, Jalan Bukit Bintang, Kuala Lumpur');
      expect(claim.latitude, 3.14);
      expect(claim.longitude, 101.69);
      viewModel.dispose();
    });

    test('an address claim with no map carries no coordinates', () async {
      final _FakeReportLogicFacade logic = _FakeReportLogicFacade();
      final ReportPlaceViewModel viewModel = build(logic);
      viewModel.selectCategory(ReportCategory.address);
      viewModel.setAddressText('12, Jalan Bukit Bintang, Kuala Lumpur');

      await viewModel.submit();

      final ReportClaim claim = logic.submittedClaims.single;
      expect(claim.latitude, isNull);
      expect(claim.longitude, isNull);
      viewModel.dispose();
    });

    test('a reporter standing at the place produces a valid claim', () async {
      // The fix the report page reads silently - at the PLACE (3.1, 101.6).
      CurrentLocationFacade().publish(place);
      addTearDown(
        () => CurrentLocationFacade().publish(TouristLocation.unknown),
      );
      final _FakeReportLogicFacade logic = _FakeReportLogicFacade();
      final ReportPlaceViewModel viewModel = build(logic, location: place);
      await viewModel.onInit();
      viewModel.selectCategory(ReportCategory.address);
      viewModel.setAddressText('12, Jalan Bukit Bintang, Kuala Lumpur');
      // They drop the correction pin 1 km away - where the pin is has no say
      // in the on-site check: the place they are reporting is what counts.
      viewModel.moveReportLocation(3.2, 101.6);

      await viewModel.submit();

      expect(logic.submittedClaims.single.locationValid, isTrue);
      viewModel.dispose();
    });

    test(
      'a reporter far from the place produces a claim that cannot count',
      () async {
        // Standing exactly where they put their pin - but a kilometre from the
        // landmark they are reporting.
        CurrentLocationFacade().publish(
          const TouristLocation(latitude: 3.2, longitude: 101.6),
        );
        addTearDown(
          () => CurrentLocationFacade().publish(TouristLocation.unknown),
        );
        final _FakeReportLogicFacade logic = _FakeReportLogicFacade();
        final ReportPlaceViewModel viewModel = build(logic, location: place);
        await viewModel.onInit();
        viewModel.selectCategory(ReportCategory.address);
        viewModel.setAddressText('12, Jalan Bukit Bintang, Kuala Lumpur');
        viewModel.moveReportLocation(3.2, 101.6);

        await viewModel.submit();

        expect(logic.submittedClaims.single.locationValid, isFalse);
        viewModel.dispose();
      },
    );
  });
}

class _TestReportPlaceViewModel extends ReportPlaceViewModel {
  _TestReportPlaceViewModel(this.logic);

  final _FakeReportLogicFacade logic;

  @override
  ReportLogicFacade createReportLogic() => logic;
}

class _FakeReportLogicFacade extends ReportLogicFacade {
  List<ReportableMenuItem> menuItems = const <ReportableMenuItem>[];
  ReportSubmitOutcome outcome = const ReportSubmitOutcome();
  List<ReportClaim> submittedClaims = <ReportClaim>[];

  /// What the pin's reverse lookup answers (null = nothing found there).
  String? mapAddress = '10, Jalan Foo, 50000 Kuala Lumpur';

  /// What the field's search answers (null = the lookup failed).
  List<AddressSuggestion>? suggestions = const <AddressSuggestion>[];
  String? lastQuery;
  TouristLocation? lastAround;

  @override
  int thresholdFor(ReportCategory category) => 1;

  @override
  Future<List<ReportableMenuItem>> reportableItemsFor({
    required ReportPlaceKind placeKind,
    required int placeId,
  }) async => menuItems;

  @override
  Future<ReportSubmitOutcome> submitClaims({
    required List<ReportClaim> claims,
    String? touristId,
  }) async {
    submittedClaims = List<ReportClaim>.of(claims);
    return outcome;
  }

  @override
  Future<List<AddressSuggestion>?> searchAddresses({
    required String query,
    required TouristLocation around,
  }) async {
    lastQuery = query;
    lastAround = around;
    return suggestions;
  }

  @override
  Future<String?> reverseGeocodeAddress(TouristLocation location) async =>
      mapAddress;
}
