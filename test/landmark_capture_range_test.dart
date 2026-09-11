import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/tourist_location.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/landmark_submission_logic.dart';

/// KL fix used as the first food's capture location in every test.
TouristLocation _location(double latitude, double longitude) =>
    TouristLocation(latitude: latitude, longitude: longitude);

void main() {
  final LandmarkSubmissionLogic logic = LandmarkSubmissionLogic();

  group('distanceMetres', () {
    test('returns 0 for the same point', () {
      expect(
        logic.distanceMetres(
          _location(3.1390, 101.6869),
          _location(3.1390, 101.6869),
        ),
        closeTo(0, 0.001),
      );
    });

    test('0.0005 degrees of latitude is ~55 m', () {
      expect(
        logic.distanceMetres(
          _location(3.1390, 101.6869),
          _location(3.1395, 101.6869),
        ),
        closeTo(55.6, 1.0),
      );
    });
  });

  group('isSameRestaurantCaptureRange (50 m rule)', () {
    test('a capture within 50 m of the first food is accepted', () {
      // ~22 m away (0.0002 lat).
      expect(
        logic.isSameRestaurantCaptureRange(
          _location(3.1390, 101.6869),
          _location(3.1392, 101.6869),
        ),
        isTrue,
      );
    });

    test('a capture more than 50 m away is rejected', () {
      // ~55 m away (0.0005 lat).
      expect(
        logic.isSameRestaurantCaptureRange(
          _location(3.1390, 101.6869),
          _location(3.1395, 101.6869),
        ),
        isFalse,
      );
    });

    test('a distance of exactly the limit is accepted', () {
      // The rule is "more than 50 m is too far" - 50 m itself is fine. The
      // point below is ~50.0 m north of the reference.
      const double latMetres = 111320; // metres per degree of latitude
      final double offset =
          LandmarkSubmissionLogic.sameRestaurantCaptureRangeMetres / latMetres;
      expect(
        logic.isSameRestaurantCaptureRange(
          _location(3.1390, 101.6869),
          _location(3.1390 + offset, 101.6869),
        ),
        isTrue,
      );
    });

    test('an unknown reference fix never blocks the capture', () {
      expect(
        logic.isSameRestaurantCaptureRange(
          TouristLocation.unknown,
          _location(3.1395, 101.6869),
        ),
        isTrue,
      );
    });

    test('an unknown capture fix never blocks the capture', () {
      expect(
        logic.isSameRestaurantCaptureRange(
          _location(3.1390, 101.6869),
          TouristLocation.unknown,
        ),
        isTrue,
      );
    });
  });

  group('captureTooFarMessage', () {
    test('names the rejected capture and the 50 m limit - kept short', () {
      for (final String what in <String>[
        'This food',
        'This signboard photo',
        'This stall photo',
      ]) {
        final String message = logic.captureTooFarMessage(what);
        expect(message, contains(what));
        expect(message, contains('50 m'));
        expect(message, contains('first food'));
        // Deliberately short and consistent with the other capture messages
        // ("No food detected in image. Please try again.") - the popup and
        // the recognition card carry their own "capture again" action
        // lines, so the message must not repeat the whole rule (the old
        // wording was almost twice this length).
        expect(message.length, lessThan(125));
      }
    });
  });
}
