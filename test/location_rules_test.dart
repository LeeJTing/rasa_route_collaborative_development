import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/malaysia_boundary.dart';
import 'package:rasa_route_collaborative_development/domain_model/region.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/location_rules.dart';

void main() {
  group('LocationRules.isWithinMalaysia', () {
    test('Peninsular Malaysia cities are inside', () {
      const List<(double, double)> inside = <(double, double)>[
        (3.1390, 101.6869), // Kuala Lumpur
        (5.4141, 100.3288), // George Town, Penang
        (1.4927, 103.7414), // Johor Bahru
        (2.1896, 102.2501), // Melaka
        (4.5975, 101.0901), // Ipoh
        (6.1239, 102.2429), // Kota Bharu
        (5.3302, 103.1408), // Kuala Terengganu
        (3.8077, 103.3260), // Kuantan
      ];
      for (final (double lat, double lon) in inside) {
        expect(
          LocationRules.isWithinMalaysia(lat, lon),
          isTrue,
          reason: '($lat, $lon) should be inside Peninsular Malaysia',
        );
      }
    });

    test('East Malaysia cities are inside', () {
      const List<(double, double)> inside = <(double, double)>[
        (5.9804, 116.0735), // Kota Kinabalu
        (1.5535, 110.3593), // Kuching
        (4.2448, 117.8911), // Tawau
        (5.8394, 118.1172), // Sandakan
        (2.2873, 111.8276), // Sibu
      ];
      for (final (double lat, double lon) in inside) {
        expect(
          LocationRules.isWithinMalaysia(lat, lon),
          isTrue,
          reason: '($lat, $lon) should be inside East Malaysia',
        );
      }
    });

    test('islands and the Perlis coast are inside too (user report)', () {
      const List<(double, double)> inside = <(double, double)>[
        (5.7730, 103.0080), // Pulau Redang, Terengganu
        (5.9100, 102.7300), // Perhentian Besar
        (6.4410, 100.1980), // Kangar, Perlis
        (6.4000, 100.1280), // Kuala Perlis
        (6.3520, 99.8020), // Kuah, Langkawi
        (2.7900, 104.1690), // Pulau Tioman, Pahang
        (4.1150, 118.6290), // Pulau Sipadan, Sabah
      ];
      for (final (double lat, double lon) in inside) {
        expect(
          LocationRules.isWithinMalaysia(lat, lon),
          isTrue,
          reason:
              '($lat, $lon) is Malaysian land - the map draws it inside the '
              'country, so the Add-Landmark check must accept it',
        );
      }
    });

    test('the rings the map publishes win while they are set', () {
      // A spot the built-in polygons reject (Gulf of Thailand)...
      expect(LocationRules.isWithinMalaysia(6.60, 103.50), isFalse);
      // ...is accepted once the map has published rings that contain it, so
      // the form answers with the map's own dataset (see MalaysiaBoundary).
      MalaysiaBoundary.publishRings(<CountryOutline>[
        const CountryOutline(
          name: 'published test ring',
          ring: <GeoPoint>[
            GeoPoint(6.90, 103.20),
            GeoPoint(6.90, 103.80),
            GeoPoint(6.30, 103.80),
            GeoPoint(6.30, 103.20),
          ],
        ),
      ]);
      expect(LocationRules.isWithinMalaysia(6.60, 103.50), isTrue);
      // Outside the published rings the answer is their "no" - not the
      // fallback's "yes".
      expect(LocationRules.isWithinMalaysia(3.1390, 101.6869), isFalse);
      // With nothing published the built-in polygons answer again.
      MalaysiaBoundary.forgetRings();
      expect(LocationRules.isWithinMalaysia(3.1390, 101.6869), isTrue);
      expect(LocationRules.isWithinMalaysia(6.60, 103.50), isFalse);
    });

    test('neighbouring countries and open sea are outside', () {
      const List<(double, double)> outside = <(double, double)>[
        (1.3521, 103.8198), // Singapore
        (13.7563, 100.5018), // Bangkok, Thailand
        (-6.2088, 106.8456), // Jakarta, Indonesia
        (8.0, 112.0), // South China Sea
        (3.0, 100.2), // Straits of Malacca
        (6.0, 98.5), // Andaman Sea
        (6.6, 103.5), // Gulf of Thailand
        (0.5, 101.0), // Sumatra, Indonesia
      ];
      for (final (double lat, double lon) in outside) {
        expect(
          LocationRules.isWithinMalaysia(lat, lon),
          isFalse,
          reason: '($lat, $lon) should be outside Malaysia',
        );
      }
    });

    test('isOnLand agrees with the boundary for these samples', () {
      // Malaysian land -> on land.
      expect(LocationRules.isOnLand(3.1390, 101.6869), isTrue); // KL
      expect(LocationRules.isOnLand(5.9804, 116.0735), isTrue); // Kota Kinabalu
      // Outside Malaysia / at sea -> not on land.
      expect(LocationRules.isOnLand(1.3521, 103.8198), isFalse); // Singapore
      expect(LocationRules.isOnLand(3.0, 100.2), isFalse); // Straits of Malacca
    });
  });
}
