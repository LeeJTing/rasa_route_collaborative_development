import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/opening_hour.dart';
import 'package:rasa_route_collaborative_development/model/repositories/submitted_landmark_repository.dart';

/// Merge update rule (A13 contact-field persistence): when a tourist
/// re-submits an EXISTING submitted landmark, only fields the re-submission
/// actually changed may be written. A second submission that lacks a field
/// (empty) must NOT overwrite a value an earlier submission stored, and a
/// field the second submission did not change (same value) is left alone.

OpeningHour _hour(
  Weekday day,
  DayStatus status, [
  int? opensAt,
  int? closesAt,
]) => OpeningHour(
  id: 0,
  day: day,
  status: status,
  opensAt: opensAt,
  closesAt: closesAt,
);

void main() {
  group('changedContactFields (A13 merge, never clobber richer data)', () {
    test(
      'writes nothing when the second submission carries no contact fields',
      () {
        expect(
          SubmittedLandmarkRepository.changedContactFields(
            storedPhone: '012-345 6789',
            storedWebsite: 'https://tianyikopitiam.my',
            storedAddress: '12, Jalan Alor, Kuala Lumpur',
            phone: null,
            website: null,
            address: null,
          ),
          isEmpty,
        );
      },
    );

    test(
      'writes nothing when the second submission fields are blank strings',
      () {
        expect(
          SubmittedLandmarkRepository.changedContactFields(
            storedPhone: '012-345 6789',
            storedWebsite: 'https://tianyikopitiam.my',
            storedAddress: '12, Jalan Alor, Kuala Lumpur',
            phone: '',
            website: '   ',
            address: '',
          ),
          isEmpty,
        );
      },
    );

    test(
      'writes nothing when the second submission repeats the stored values',
      () {
        expect(
          SubmittedLandmarkRepository.changedContactFields(
            storedPhone: '012-345 6789',
            storedWebsite: 'https://tianyikopitiam.my',
            storedAddress: '12, Jalan Alor, Kuala Lumpur',
            phone: '012-345 6789',
            website: 'https://tianyikopitiam.my',
            address: '12, Jalan Alor, Kuala Lumpur',
          ),
          isEmpty,
        );
      },
    );

    test('writes only the single field that actually changed', () {
      final Map<String, Object?> values =
          SubmittedLandmarkRepository.changedContactFields(
            storedPhone: '012-345 6789',
            storedWebsite: 'https://tianyikopitiam.my',
            storedAddress: '12, Jalan Alor, Kuala Lumpur',
            phone: '012-999 8888', // changed
            website: 'https://tianyikopitiam.my', // same -> untouched
            address: null, // not supplied -> untouched
          );
      expect(values, <String, Object?>{'phone': '012-999 8888'});
    });

    test('writes the fields the second submission newly supplies', () {
      final Map<String, Object?> values =
          SubmittedLandmarkRepository.changedContactFields(
            storedPhone: null,
            storedWebsite: null,
            storedAddress: null,
            phone: '012-345 6789',
            website: 'https://tianyikopitiam.my',
            address: '12, Jalan Alor, Kuala Lumpur',
          );
      expect(values, <String, Object?>{
        'phone': '012-345 6789',
        'website': 'https://tianyikopitiam.my',
        'address': '12, Jalan Alor, Kuala Lumpur',
      });
    });

    test('trims submitted values before comparing and storing', () {
      final Map<String, Object?> values =
          SubmittedLandmarkRepository.changedContactFields(
            storedPhone: '012-345 6789',
            storedWebsite: null,
            storedAddress: '12, Jalan Alor, Kuala Lumpur',
            phone: '  012-345 6789  ', // same after trim -> untouched
            website: '  https://tianyikopitiam.my  ', // newly supplied
            address: '12, Jalan Alor, Kuala Lumpur', // same -> untouched
          );
      expect(values, <String, Object?>{'website': 'https://tianyikopitiam.my'});
    });

    test('writes a field whose value genuinely changed (new formatting)', () {
      // e.g. the stored phone was entered without dashes; the re-submission
      // supplies the same number formatted differently -> a real change on
      // that field, so it is written.
      final Map<String, Object?> values =
          SubmittedLandmarkRepository.changedContactFields(
            storedPhone: '0123456789',
            storedWebsite: null,
            storedAddress: null,
            phone: '012-345 6789',
            website: null,
            address: null,
          );
      expect(values, <String, Object?>{'phone': '012-345 6789'});
    });

    test('a case- or spacing-only difference is not a change', () {
      // The SAME detail written in another case (or with a double space) is
      // not an edit - it must not rewrite the stored row, and it must not
      // raise the merge's overwrite question (user request 2026-09-14: every
      // such check folds case first).
      expect(
        SubmittedLandmarkRepository.changedContactFields(
          storedPhone: '012-345 6789',
          storedWebsite: 'https://TianYiKopitiam.my',
          storedAddress: '12, Jalan Ampang,  Kuala Lumpur',
          phone: '012-345 6789',
          website: 'https://tianyikopitiam.my',
          address: '12, jalan ampang, kuala lumpur',
        ),
        isEmpty,
      );
    });

    test('a real edit on the same field is still written', () {
      // Case folding must never swallow content: the postal code is new.
      final Map<String, Object?> values =
          SubmittedLandmarkRepository.changedContactFields(
            storedPhone: null,
            storedWebsite: null,
            storedAddress: '12, Jalan Ampang, Kuala Lumpur',
            phone: null,
            website: null,
            address: '12, Jalan Ampang, Kuala Lumpur 50450',
          );
      expect(values, <String, Object?>{
        'address': '12, Jalan Ampang, Kuala Lumpur 50450',
      });
    });
  });

  group('changedOpeningHourDays (A13 merge, per-day hours update)', () {
    // Stored landmark: Mon open 09:00-... , Tue-Fri open 09:00-14:00.
    Map<Weekday, List<OpeningHour>> storedWeek() =>
        <Weekday, List<OpeningHour>>{
          Weekday.monday: <OpeningHour>[
            _hour(Weekday.monday, DayStatus.open, 540, 1540), // 09:00-01:40
          ],
          Weekday.tuesday: <OpeningHour>[
            _hour(Weekday.tuesday, DayStatus.open, 540, 840), // 09:00-14:00
          ],
          Weekday.wednesday: <OpeningHour>[
            _hour(Weekday.wednesday, DayStatus.open, 540, 840),
          ],
          Weekday.thursday: <OpeningHour>[
            _hour(Weekday.thursday, DayStatus.open, 540, 840),
          ],
          Weekday.friday: <OpeningHour>[
            _hour(Weekday.friday, DayStatus.open, 540, 840),
          ],
        };

    test('updates only Monday when the second submission changes Monday and '
        'leaves the rest Unknown (never clobbers Tue-Fri)', () {
      final Map<Weekday, List<OpeningHour>> submitted =
          <Weekday, List<OpeningHour>>{
            for (final Weekday day in Weekday.values)
              day: <OpeningHour>[
                _hour(day, DayStatus.unknown), // all days default Unknown
              ],
          };
      // Tourist changes Monday to 12:00-16:00, leaves everything else
      // Unknown - exactly the user's scenario.
      submitted[Weekday.monday] = <OpeningHour>[
        _hour(Weekday.monday, DayStatus.open, 720, 960),
      ];
      expect(
        SubmittedLandmarkRepository.changedOpeningHourDays(
          storedByDay: storedWeek(),
          submitted: submitted,
        ),
        <Weekday>{Weekday.monday},
      );
    });

    test('writes nothing when every submitted day is left Unknown', () {
      final Map<Weekday, List<OpeningHour>> submitted =
          <Weekday, List<OpeningHour>>{
            for (final Weekday day in Weekday.values)
              day: <OpeningHour>[_hour(day, DayStatus.unknown)],
          };
      expect(
        SubmittedLandmarkRepository.changedOpeningHourDays(
          storedByDay: storedWeek(),
          submitted: submitted,
        ),
        isEmpty,
      );
    });

    test('writes nothing when the submission repeats the stored hours', () {
      expect(
        SubmittedLandmarkRepository.changedOpeningHourDays(
          storedByDay: storedWeek(),
          submitted: storedWeek(),
        ),
        isEmpty,
      );
    });

    test('only the single day that changed is selected', () {
      final Map<Weekday, List<OpeningHour>> submitted = storedWeek();
      // Tourist corrects Thursday only to 10:00-18:00.
      submitted[Weekday.thursday] = <OpeningHour>[
        _hour(Weekday.thursday, DayStatus.open, 600, 1080),
      ];
      expect(
        SubmittedLandmarkRepository.changedOpeningHourDays(
          storedByDay: storedWeek(),
          submitted: submitted,
        ),
        <Weekday>{Weekday.thursday},
      );
    });

    test(
      'an open day split into two ranges counts as changed vs one range',
      () {
        final Map<Weekday, List<OpeningHour>> stored =
            <Weekday, List<OpeningHour>>{
              Weekday.monday: <OpeningHour>[
                _hour(Weekday.monday, DayStatus.open, 540, 840),
              ],
            };
        final Map<Weekday, List<OpeningHour>> submitted =
            <Weekday, List<OpeningHour>>{
              for (final Weekday day in Weekday.values)
                day: <OpeningHour>[_hour(day, DayStatus.unknown)],
              Weekday.monday: <OpeningHour>[
                _hour(Weekday.monday, DayStatus.open, 540, 720),
                _hour(Weekday.monday, DayStatus.open, 780, 840),
              ],
            };
        expect(
          SubmittedLandmarkRepository.changedOpeningHourDays(
            storedByDay: stored,
            submitted: submitted,
          ),
          <Weekday>{Weekday.monday},
        );
      },
    );

    test('same multi-range rows in a different order are NOT a change', () {
      final Map<Weekday, List<OpeningHour>> stored =
          <Weekday, List<OpeningHour>>{
            Weekday.monday: <OpeningHour>[
              _hour(Weekday.monday, DayStatus.open, 540, 720),
              _hour(Weekday.monday, DayStatus.open, 780, 840),
            ],
          };
      final Map<Weekday, List<OpeningHour>> submitted =
          <Weekday, List<OpeningHour>>{
            for (final Weekday day in Weekday.values)
              day: <OpeningHour>[_hour(day, DayStatus.unknown)],
            Weekday.monday: <OpeningHour>[
              _hour(Weekday.monday, DayStatus.open, 780, 840),
              _hour(Weekday.monday, DayStatus.open, 540, 720),
            ],
          };
      expect(
        SubmittedLandmarkRepository.changedOpeningHourDays(
          storedByDay: stored,
          submitted: submitted,
        ),
        isEmpty,
      );
    });

    test('a day asserted Closed replaces a stored Open day', () {
      final Map<Weekday, List<OpeningHour>> submitted = storedWeek();
      submitted[Weekday.sunday] = <OpeningHour>[
        _hour(Weekday.sunday, DayStatus.closed),
      ];
      expect(
        SubmittedLandmarkRepository.changedOpeningHourDays(
          storedByDay: storedWeek(),
          submitted: submitted,
        ),
        <Weekday>{Weekday.sunday},
      );
    });

    test('a newly-asserted day with no stored rows is selected', () {
      final Map<Weekday, List<OpeningHour>> submitted =
          <Weekday, List<OpeningHour>>{
            for (final Weekday day in Weekday.values)
              day: <OpeningHour>[_hour(day, DayStatus.unknown)],
            Weekday.saturday: <OpeningHour>[
              _hour(Weekday.saturday, DayStatus.open, 600, 1080),
            ],
          };
      expect(
        SubmittedLandmarkRepository.changedOpeningHourDays(
          storedByDay: storedWeek(), // stored has no Saturday rows
          submitted: submitted,
        ),
        <Weekday>{Weekday.saturday},
      );
    });
  });
}
