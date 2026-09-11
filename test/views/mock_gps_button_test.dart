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
}
