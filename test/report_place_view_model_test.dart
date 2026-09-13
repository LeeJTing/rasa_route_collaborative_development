import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/opening_hour.dart';
import 'package:rasa_route_collaborative_development/domain_model/report_category.dart';
import 'package:rasa_route_collaborative_development/domain_model/report_claim.dart';
import 'package:rasa_route_collaborative_development/domain_model/report_outcome.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/report_logic_facade.dart';
import 'package:rasa_route_collaborative_development/view_models/report_place_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ReportPlaceViewModel build(
    _FakeReportLogicFacade logic, {
    ReportPlaceKind kind = ReportPlaceKind.restaurant,
    int placeId = 1,
    String name = 'OldTown',
  }) {
    final ReportPlaceViewModel viewModel = _TestReportPlaceViewModel(logic);
    viewModel.configure(kind, placeId, name);
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
        viewModel.setAddressText('Some address');
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
}
