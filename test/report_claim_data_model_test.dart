import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/model/data_models/report_claim_data_model.dart';

/// The wire shape of one `report` row (see `ReportClaimDataModel`) - the
/// layer `ReportRepository` converts every read and every insert through, so
/// these tests pin the column names and the defensive parsing the repository
/// depends on.
void main() {
  group('ReportClaimDataModel (report row wire shape)', () {
    test('round-trips a full row', () {
      final Map<String, dynamic> json = <String, dynamic>{
        'report_id': 12,
        'kind': 'landmark',
        'place_id': 333,
        'reason': 'itemPrice',
        'item_kind': 'landmark_item',
        'item_id': 1033,
        'day': 'monday',
        'payload': '9.00',
        'latitude': 6.4414,
        'longitude': 100.1987,
        'location_valid': true,
        'tourist_id': '3c0c1914-020e-4e83-9657-98e23d45dd17',
        'created_at': '2026-09-14T07:30:00.000Z',
      };

      final ReportClaimDataModel model = ReportClaimDataModel.fromJson(json);

      expect(model.reportId, 12);
      expect(model.kind, 'landmark');
      expect(model.placeId, 333);
      expect(model.reason, 'itemPrice');
      expect(model.itemKind, 'landmark_item');
      expect(model.itemId, 1033);
      expect(model.day, 'monday');
      expect(model.payload, '9.00');
      expect(model.latitude, 6.4414);
      expect(model.longitude, 100.1987);
      expect(model.locationValid, isTrue);
      expect(model.createdAt, DateTime.parse('2026-09-14T07:30:00.000Z'));
      expect(model.toJson(), json);
    });

    test('parses the narrow projections the repository selects', () {
      // The count / already-reported queries read only the wire id and the
      // expiry clock - everything else is absent and must stay null instead
      // of throwing.
      final ReportClaimDataModel row = ReportClaimDataModel.fromJson(
        <String, dynamic>{
          'report_id': 7,
          'created_at': '2026-09-14T07:30:00.000Z',
        },
      );

      expect(row.reportId, 7);
      expect(row.createdAt, isNotNull);
      expect(row.kind, '');
      expect(row.placeId, 0);
      expect(row.itemId, isNull);
      expect(row.latitude, isNull);
      expect(row.locationValid, isFalse);
      expect(row.touristId, isNull);
    });

    test('absorbs the stringified values Supabase sometimes returns', () {
      final ReportClaimDataModel row =
          ReportClaimDataModel.fromJson(<String, dynamic>{
            'place_id': '12',
            'latitude': '6.4414',
            'longitude': '100.1987',
            'location_valid': 'true',
          });

      expect(row.placeId, 12);
      expect(row.latitude, 6.4414);
      expect(row.longitude, 100.1987);
      expect(row.locationValid, isTrue);
      expect(row.createdAt, isNull);
    });

    test('an insert-shaped row leaves the DB-owned columns null', () {
      // `ReportRepository.insertClaim` builds this shape and compacts it:
      // `report_id` (identity) and `created_at` (default now()) are the
      // database's to fill.
      final Map<String, dynamic> json = const ReportClaimDataModel(
        kind: 'restaurant',
        placeId: 9865,
        reason: 'closedPermanently',
        locationValid: true,
        touristId: '3c0c1914-020e-4e83-9657-98e23d45dd17',
      ).toJson();

      expect(json['report_id'], isNull);
      expect(json['created_at'], isNull);
      expect(json['item_kind'], isNull);
      expect(json['payload'], isNull);
      expect(json['kind'], 'restaurant');
      expect(json['reason'], 'closedPermanently');
    });
  });
}
