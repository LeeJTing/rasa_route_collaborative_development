import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/landmark_submission_logic.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/restaurant_discovery_logic.dart';

void main() {
  group('report freeze threshold (shared 5-report rule)', () {
    test('keeps a place available through 4 reports', () {
      for (int count = 0; count <= 4; count++) {
        expect(
          LandmarkSubmissionLogic.shouldFreezeAfterReport(count),
          isFalse,
          reason: 'landmark with $count reports must stay available',
        );
        expect(
          RestaurantDiscoveryLogic.shouldFreezeAfterReport(count),
          isFalse,
          reason: 'restaurant with $count reports must stay available',
        );
      }
    });

    test('freezes on the 5th report', () {
      expect(LandmarkSubmissionLogic.shouldFreezeAfterReport(5), isTrue);
      expect(RestaurantDiscoveryLogic.shouldFreezeAfterReport(5), isTrue);
    });

    test('stays frozen once past the threshold', () {
      expect(LandmarkSubmissionLogic.shouldFreezeAfterReport(100), isTrue);
      expect(RestaurantDiscoveryLogic.shouldFreezeAfterReport(100), isTrue);
    });
  });
}
