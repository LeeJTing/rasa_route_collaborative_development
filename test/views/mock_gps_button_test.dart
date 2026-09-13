import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/views/common_widgets/mock_gps_button.dart';

/// [MockGpsButton.offsetBy] is the maths behind the presenter tool's "walk
/// 60 m" chips - the one-tap way to demo the 50 m same-restaurant rule
/// without moving the device.
void main() {
  const double lat = 3.1390;
  const double lon = 101.6869;

  group('MockGpsButton.offsetBy', () {
    test('north then south lands back on the same spot', () {
      final ({double lat, double lon}) north = MockGpsButton.offsetBy(
        lat,
        lon,
        northMetres: MockGpsButton.nudgeMetres,
      );
      expect(north.lat, greaterThan(lat));
      expect(north.lon, closeTo(lon, 1e-9));

      final ({double lat, double lon}) back = MockGpsButton.offsetBy(
        north.lat,
        north.lon,
        northMetres: -MockGpsButton.nudgeMetres,
      );
      expect(back.lat, closeTo(lat, 1e-9));
      expect(back.lon, closeTo(lon, 1e-9));
    });

    test('the nudge is far enough to break the 50 m same-restaurant rule', () {
      final ({double lat, double lon}) north = MockGpsButton.offsetBy(
        lat,
        lon,
        northMetres: MockGpsButton.nudgeMetres,
      );
      // 60 m of latitude is 60/111320 degrees - comfortably over the 50 m
      // rule's radius once the logic measures it.
      expect((north.lat - lat) * 111320, closeTo(60, 0.5));
      expect(MockGpsButton.nudgeMetres, greaterThan(50));
    });

    test('a longitude degree is shorter than a latitude degree', () {
      final ({double lat, double lon}) north = MockGpsButton.offsetBy(
        lat,
        lon,
        northMetres: 60,
      );
      final ({double lat, double lon}) east = MockGpsButton.offsetBy(
        lat,
        lon,
        eastMetres: 60,
      );
      // Same metres east needs MORE degrees than north at this latitude.
      expect((east.lon - lon).abs(), greaterThan((north.lat - lat).abs()));
    });

    test('no offset leaves the point untouched', () {
      final ({double lat, double lon}) same = MockGpsButton.offsetBy(lat, lon);
      expect(same.lat, lat);
      expect(same.lon, lon);
    });
  });

  group('MockGpsButton.presetGroups', () {
    Map<String, List<String>> byState() => <String, List<String>>{
      for (final ({
            String state,
            List<({String label, double lat, double lon})> spots,
          })
          group
          in MockGpsButton.presetGroups)
        group.state: <String>[
          for (final ({String label, double lat, double lon}) spot
              in group.spots)
            spot.label,
        ],
    };

    test('separates the demo districts by state', () {
      final Map<String, List<String>> states = byState();

      expect(
        states.keys,
        containsAll(<String>['Kuala Lumpur', 'Selangor', 'Johor']),
      );
      expect(
        states['Kuala Lumpur'],
        containsAll(<String>['KL', 'Setapak', 'Cheras', 'Ampang']),
      );
      expect(
        states['Selangor'],
        containsAll(<String>['Subang Jaya', 'Shah Alam', 'Klang']),
      );
      expect(
        states['Johor'],
        containsAll(<String>['Johor Bahru', 'Skudai', 'Batu Pahat']),
      );
    });

    test('keeps the refusal-test spots in their own group', () {
      expect(
        byState()['Refusal tests'],
        containsAll(<String>['Outside MY', 'At sea']),
      );
    });

    test('every spot is uniquely labelled', () {
      final List<String> labels = <String>[
        for (final List<String> stateLabels in byState().values) ...stateLabels,
      ];
      expect(labels.toSet(), hasLength(labels.length));
    });
  });

  testWidgets('the picker shows one section per state and sets a district', (
    WidgetTester tester,
  ) async {
    double? mockedLatitude;
    double? mockedLongitude;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MockGpsButton(
            isActive: false,
            onSetMock: (double latitude, double longitude) async {
              mockedLatitude = latitude;
              mockedLongitude = longitude;
              return null;
            },
            onStopMock: () async {},
          ),
        ),
      ),
    );

    await tester.tap(find.byType(MockGpsButton));
    await tester.pumpAndSettle();

    // One header per state, not one flat list of chips.
    expect(find.text('Kuala Lumpur'), findsOneWidget);
    expect(find.text('Selangor'), findsOneWidget);
    expect(find.text('Johor'), findsOneWidget);
    expect(find.text('Refusal tests'), findsOneWidget);

    // Tapping a district teleports the mock to ITS coordinates.
    await tester.tap(find.text('Setapak'));
    await tester.pumpAndSettle();

    expect(mockedLatitude, 3.1930);
    expect(mockedLongitude, 101.7120);
  });
}
