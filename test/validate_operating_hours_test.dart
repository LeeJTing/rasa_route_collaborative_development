import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/opening_hour.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/landmark_submission_logic.dart';
import 'package:rasa_route_collaborative_development/view_models/add_landmark_view_model.dart';

void main() {
  test('two separate ranges on Monday are valid (03:00-03:30 & 05:00-05:30)', () {
    final LandmarkSubmissionLogic logic = LandmarkSubmissionLogic();
    final Map<Weekday, List<OpeningHour>> hours = <Weekday, List<OpeningHour>>{
      Weekday.monday: <OpeningHour>[
        OpeningHour(
          id: 0,
          day: Weekday.monday,
          status: DayStatus.open,
          opensAt: 3 * 60, // 03:00
          closesAt: 3 * 60 + 30, // 03:30
        ),
        OpeningHour(
          id: 0,
          day: Weekday.monday,
          status: DayStatus.open,
          opensAt: 5 * 60, // 05:00
          closesAt: 5 * 60 + 30, // 05:30
        ),
      ],
    };
    expect(logic.validateOperatingHours(hours), isNull);
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
}
