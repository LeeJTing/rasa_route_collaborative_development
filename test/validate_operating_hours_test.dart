import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/local_food.dart';
import 'package:rasa_route_collaborative_development/domain_model/opening_hour.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/landmark_submission_logic.dart';
import 'package:rasa_route_collaborative_development/view_models/add_landmark_view_model.dart';

LocalFood _food([String name = 'Nasi Lemak']) => LocalFood(
  id: 0,
  name: name,
  description: '',
  origin: '',
  culturalBackground: '',
  ingredients: '',
  category: 'Malay',
  cookingStyle: '',
  mealType: '',
  foodType: 'Food',
);

void main() {
  test(
    'two separate ranges on Monday are valid (03:00-04:30 & 05:00-06:00)',
    () {
      final LandmarkSubmissionLogic logic = LandmarkSubmissionLogic();
      final Map<Weekday, List<OpeningHour>> hours =
          <Weekday, List<OpeningHour>>{
            Weekday.monday: <OpeningHour>[
              OpeningHour(
                id: 0,
                day: Weekday.monday,
                status: DayStatus.open,
                opensAt: 3 * 60, // 03:00
                closesAt: 4 * 60 + 30, // 04:30
              ),
              OpeningHour(
                id: 0,
                day: Weekday.monday,
                status: DayStatus.open,
                opensAt: 5 * 60, // 05:00
                closesAt: 6 * 60, // 06:00
              ),
            ],
          };
      expect(logic.validateOperatingHours(hours), isNull);
    },
  );

  test('a row shorter than one hour is rejected', () {
    final LandmarkSubmissionLogic logic = LandmarkSubmissionLogic();
    final Map<Weekday, List<OpeningHour>> hours = <Weekday, List<OpeningHour>>{
      Weekday.monday: <OpeningHour>[
        OpeningHour(
          id: 0,
          day: Weekday.monday,
          status: DayStatus.open,
          opensAt: 9 * 60, // 09:00
          closesAt: 9 * 60 + 30, // 09:30 - half an hour
        ),
      ],
    };

    final String? error = logic.validateOperatingHours(hours);
    expect(error, isNotNull);
    expect(error, contains('shorter than 1 hour'));
    expect(error, contains('09:00-09:30'));
  });

  test('a single one-hour row is accepted', () {
    final LandmarkSubmissionLogic logic = LandmarkSubmissionLogic();
    final Map<Weekday, List<OpeningHour>> hours = <Weekday, List<OpeningHour>>{
      Weekday.monday: <OpeningHour>[
        OpeningHour(
          id: 0,
          day: Weekday.monday,
          status: DayStatus.open,
          opensAt: 14 * 60,
          closesAt: 15 * 60, // exactly one hour
        ),
      ],
    };
    expect(logic.validateOperatingHours(hours), isNull);
  });

  test('contiguous rows (09:00-12:00 + 12:00-14:00) are rejected and tell the '
      'tourist to combine them', () {
    final LandmarkSubmissionLogic logic = LandmarkSubmissionLogic();
    final Map<Weekday, List<OpeningHour>> hours = <Weekday, List<OpeningHour>>{
      Weekday.monday: <OpeningHour>[
        OpeningHour(
          id: 0,
          day: Weekday.monday,
          status: DayStatus.open,
          opensAt: 9 * 60, // 09:00
          closesAt: 12 * 60, // 12:00
        ),
        OpeningHour(
          id: 0,
          day: Weekday.monday,
          status: DayStatus.open,
          opensAt: 12 * 60, // 12:00 - starts exactly when the first ends
          closesAt: 14 * 60, // 14:00
        ),
      ],
    };

    final String? error = logic.validateOperatingHours(hours);
    expect(error, isNotNull);
    expect(error, contains('continuous'));
    expect(error, contains('combine them into one row 09:00-14:00'));
  });

  test('overlapping rows are still rejected', () {
    final LandmarkSubmissionLogic logic = LandmarkSubmissionLogic();
    final Map<Weekday, List<OpeningHour>> hours = <Weekday, List<OpeningHour>>{
      Weekday.monday: <OpeningHour>[
        OpeningHour(
          id: 0,
          day: Weekday.monday,
          status: DayStatus.open,
          opensAt: 12 * 60,
          closesAt: 15 * 60,
        ),
        OpeningHour(
          id: 0,
          day: Weekday.monday,
          status: DayStatus.open,
          opensAt: 14 * 60,
          closesAt: 18 * 60,
        ),
      ],
    };
    expect(logic.validateOperatingHours(hours), contains('overlap'));
  });

  test('ViewModel stores two ranges as two separate rows', () async {
    final AddLandmarkViewModel vm = AddLandmarkViewModel();
    await vm.onInit();
    vm.setDayStatus(Weekday.monday, DayStatus.open);
    vm.addTimeRange(Weekday.monday); // now 2 rows for Monday

    // Row 0: 03:00 - 03:30
    vm.setRangeTime(Weekday.monday, 0, true, 3 * 60);
    vm.setRangeTime(Weekday.monday, 0, false, 3 * 60 + 30);
    // Row 1: 05:00 - 05:30
    vm.setRangeTime(Weekday.monday, 1, true, 5 * 60);
    vm.setRangeTime(Weekday.monday, 1, false, 5 * 60 + 30);

    final List<OpeningHour> monday = vm.operatingHours[Weekday.monday]!;
    // ignore: avoid_print
    for (int i = 0; i < monday.length; i++) {
      // ignore: avoid_print
      print(
        'row $i: ${monday[i].opensAt} - ${monday[i].closesAt} '
        '(${monday[i].status})',
      );
    }

    expect(monday.length, 2);
    expect(monday[0].opensAt, 180);
    expect(monday[0].closesAt, 210);
    expect(monday[1].opensAt, 300);
    expect(monday[1].closesAt, 330);
    vm.dispose();
  });

  test(
    'suggestedPriceWarning warns only outside Gemini\'s suggested range',
    () {
      final LandmarkSubmissionLogic logic = LandmarkSubmissionLogic();

      expect(logic.suggestedPriceWarning('Nasi Lemak', 5.0, 2.0, 8.0), isNull);
      expect(
        logic.suggestedPriceWarning('Nasi Lemak', 500.0, 2.0, 8.0),
        contains('Suggested price'),
      );
      expect(
        logic.suggestedPriceWarning('Nasi Lemak', 0.5, 2.0, 8.0),
        contains('RM 2.00 - RM 8.00'),
      );
    },
  );

  test('suggestedPriceWarning returns null when no range is known', () {
    final LandmarkSubmissionLogic logic = LandmarkSubmissionLogic();

    expect(logic.suggestedPriceWarning('Nasi Lemak', 100.0, 0, 0), isNull);
  });

  test('suggestedPriceRangeText formats a known range and hides unknowns', () {
    final LandmarkSubmissionLogic logic = LandmarkSubmissionLogic();

    expect(
      logic.suggestedPriceRangeText(2.0, 8.0),
      'Suggested price: RM 2.00 - RM 8.00',
    );
    // A single-point range reads as one value, not "x - x".
    expect(logic.suggestedPriceRangeText(4.5, 4.5), 'Suggested price: RM 4.50');
    expect(logic.suggestedPriceRangeText(0, 8.0), isNull);
    expect(logic.suggestedPriceRangeText(0, 0), isNull);
    expect(logic.suggestedPriceRangeText(8.0, 2.0), isNull);
  });

  test('primary food price warning is set and cleared by the range', () async {
    final AddLandmarkViewModel vm = AddLandmarkViewModel();
    await vm.onInit();
    vm.setRecognizedFood(_food(), priceMin: 2.0, priceMax: 8.0);

    vm.setPrimaryFoodPrice(5.0);
    expect(vm.primaryFoodPriceWarning, isNull);

    vm.setPrimaryFoodPrice(500.0); // likely a typo
    expect(vm.primaryFoodPriceWarning, contains('Suggested price'));

    vm.setPrimaryFoodPrice(6.0); // corrected back into range
    expect(vm.primaryFoodPriceWarning, isNull);

    vm.dispose();
  });

  test(
    'the suggested range line is available even while no valid price is entered',
    () async {
      final AddLandmarkViewModel vm = AddLandmarkViewModel();
      await vm.onInit();
      vm.setRecognizedFood(_food(), priceMin: 2.0, priceMax: 8.0);

      // Known from recognition - shown under the field whether or not the
      // typed price is valid (see `_PriceField.suggestedRange`).
      expect(
        vm.primaryFoodSuggestedPriceText,
        'Suggested price: RM 2.00 - RM 8.00',
      );

      vm.addAdditionalFood(_food('Teh Tarik'), priceMin: 3.0, priceMax: 6.0);
      final int entryId = vm.additionalFoods.single.entryId;
      expect(
        vm.additionalFoodSuggestedPriceText(entryId),
        'Suggested price: RM 3.00 - RM 6.00',
      );
      vm.dispose();
    },
  );
}
