import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/address_suggestion.dart';
import 'package:rasa_route_collaborative_development/domain_model/tourist_location.dart';
import 'package:rasa_route_collaborative_development/model/business_logic/landmark_submission_logic.dart';
import 'package:rasa_route_collaborative_development/model/repositories/geocoding_repository.dart';

void main() {
  group('GeocodingRepository.composeAddress (DB-style address)', () {
    test('building name + suburb + postcode city + federal territory', () {
      // The real shape a Nominatim reverse of the "PV18" spot returns.
      expect(
        GeocodingRepository.composeAddress(<String, dynamic>{
          'name': 'PV18 Residences',
          'address': <String, dynamic>{
            'suburb': 'Setapak',
            'city': 'Kuala Lumpur',
            'postcode': '53000',
            'ISO3166-2-lvl4': 'MY-14',
          },
        }),
        'PV18 Residences, Setapak, 53000 Kuala Lumpur, '
        'Wilayah Persekutuan Kuala Lumpur',
      );
    });

    test('house number, road, area, postcode city and state', () {
      // Mirrors the existing restaurant rows ("16, Jalan Sri Damak 18,
      // Taman Sri Andalas, 41200 Klang, Selangor").
      expect(
        GeocodingRepository.composeAddress(<String, dynamic>{
          'address': <String, dynamic>{
            'house_number': '16',
            'road': 'Jalan Sri Damak 18',
            'suburb': 'Taman Sri Andalas',
            'postcode': '41200',
            'city': 'Klang',
            'state': 'Selangor',
          },
        }),
        '16, Jalan Sri Damak 18, Taman Sri Andalas, 41200 Klang, Selangor',
      );
    });

    test('a POI keeps its name and its road', () {
      expect(
        GeocodingRepository.composeAddress(<String, dynamic>{
          'name': 'AEON BiG',
          'address': <String, dynamic>{
            'road': 'Jalan Danau Saujana',
            'suburb': 'Setapak',
            'city': 'Kuala Lumpur',
            'postcode': '53000',
            'ISO3166-2-lvl4': 'MY-14',
          },
        }),
        'AEON BiG, Jalan Danau Saujana, Setapak, 53000 Kuala Lumpur, '
        'Wilayah Persekutuan Kuala Lumpur',
      );
    });

    test('collapses a name that repeats the road, and never adds Malaysia', () {
      final String composed = GeocodingRepository.composeAddress(
        <String, dynamic>{
          'name': 'Jalan PV 3',
          'address': <String, dynamic>{
            'road': 'Jalan PV 3',
            'suburb': 'Bandar Bukit Puchong 2',
            'postcode': '47120',
            'city': 'Sepang',
            'state': 'Selangor',
            'country': 'Malaysia',
          },
        },
      );
      expect(
        composed,
        'Jalan PV 3, Bandar Bukit Puchong 2, 47120 Sepang, Selangor',
      );
      expect(composed.contains('Malaysia'), isFalse);
    });

    test('skips OSM\'s "Unnamed Road" placeholder', () {
      expect(
        GeocodingRepository.composeAddress(<String, dynamic>{
          'address': <String, dynamic>{
            'road': 'Unnamed Road',
            'postcode': '89200',
            'city': 'Tuaran',
            'state': 'Sabah',
          },
        }),
        '89200 Tuaran, Sabah',
      );
    });

    test(
      'falls back to display_name (sans Malaysia) when parts are missing',
      () {
        expect(
          GeocodingRepository.composeAddress(<String, dynamic>{
            'display_name':
                'PV 10, Setapak, Kampung Padang Balang, Kuala Lumpur, Malaysia',
          }),
          'PV 10, Setapak, Kampung Padang Balang, Kuala Lumpur',
        );
      },
    );

    test(
      'trims to the 150-char column cap by dropping whole trailing parts',
      () {
        final String composed = GeocodingRepository.composeAddress(
          <String, dynamic>{
            'name': 'Long Building Name 1234567890',
            'address': <String, dynamic>{
              'road': 'Jalan Panjang Sekali 1234567890',
              'suburb': 'Taman Yang Amat Panjang 123456',
              'postcode': '12345',
              'city': 'Bandar 1234567890',
              'state': 'Wilayah Persekutuan Yang Sangat Panjang Sekali 12345',
            },
          },
        );
        expect(
          composed.length,
          lessThanOrEqualTo(GeocodingRepository.maxComposedAddressLength),
        );
        // The state was the (whole) part that had to go - never half a word.
        expect(composed.contains('Wilayah Persekutuan'), isFalse);
        expect(composed.endsWith(','), isFalse);
      },
    );

    test('returns empty when there is nothing usable', () {
      expect(
        GeocodingRepository.composeAddress(<String, dynamic>{
          'address': <String, dynamic>{'country': 'Malaysia'},
        }),
        '',
      );
    });
  });

  group('LandmarkSubmissionLogic address distances', () {
    final LandmarkSubmissionLogic logic = LandmarkSubmissionLogic();
    const TouristLocation around = TouristLocation(
      latitude: 3.1390,
      longitude: 101.6869,
    );

    test('measureAndSortSuggestions measures and orders nearest-first', () {
      final List<AddressSuggestion> sorted = logic
          .measureAndSortSuggestions(<AddressSuggestion>[
            const AddressSuggestion(
              address: 'far',
              latitude: 3.16,
              longitude: 101.72,
            ),
            const AddressSuggestion(
              address: 'near',
              latitude: 3.1393,
              longitude: 101.68695,
            ),
          ], around);
      expect(sorted.first.address, 'near');
      expect(sorted.first.distanceMeters, lessThan(100));
      expect(sorted.last.distanceMeters, greaterThan(1000));
    });

    test('formatDistance switches between m and km sensibly', () {
      expect(logic.formatDistance(0), '0 m');
      expect(logic.formatDistance(350), '350 m');
      expect(logic.formatDistance(999.6), '1.0 km');
      expect(logic.formatDistance(1400), '1.4 km');
      expect(logic.formatDistance(9999), '10.0 km');
      expect(logic.formatDistance(14300), '14 km');
      expect(logic.formatDistance(-5), '');
    });
  });
}
