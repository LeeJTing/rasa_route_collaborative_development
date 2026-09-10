import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/opening_hour.dart';
import 'package:rasa_route_collaborative_development/domain_model/restaurant.dart';
import 'package:rasa_route_collaborative_development/model/repositories/restaurant_repository.dart';

/// Exercises the REAL cache logic in `RestaurantRepository.getRestaurants()`
/// - the freshness check, the single-flight request sharing and the
/// invalidation - without a network.
///
/// The two seams production uses to reach Supabase are overridden:
/// [RestaurantRepository.fetchCatalogueRows] feeds canned rows and counts how
/// many times a "download" happened, and
/// [RestaurantRepository.currentTime] provides a controllable clock so the
/// 5-minute [RestaurantRepository.cacheTtl] can be aged without waiting.
class _FakeCatalogueRestaurantRepository extends RestaurantRepository {
  _FakeCatalogueRestaurantRepository(this._now);

  DateTime _now;
  int fetchCount = 0;

  /// Rows the next download returns. The test replaces this to simulate the
  /// database changing between reads.
  List<Restaurant> rows = const <Restaurant>[];

  /// When non-null, the next download waits on this before returning, so a
  /// test can hold a request in flight (single-flight / invalidate races).
  Completer<void>? downloadGate;

  /// When non-null, replaces the whole download body (e.g. to throw). Cleared
  /// by the test to restore the default canned-rows behaviour.
  Future<List<Restaurant>> Function()? fetchOverride;

  @override
  DateTime currentTime() => _now;

  void advance(Duration duration) => _now = _now.add(duration);

  @override
  Future<List<Restaurant>> fetchCatalogueRows() async {
    fetchCount++;
    // A real network request carries the rows that existed when it STARTED,
    // so snapshot before any gate: a test that changes [rows] while this
    // download is in flight simulates a write landing mid-download.
    final List<Restaurant> snapshot = rows;
    final Completer<void>? gate = downloadGate;
    if (gate != null) {
      downloadGate = null;
      await gate.future;
    }
    final Future<List<Restaurant>> Function()? override = fetchOverride;
    if (override != null) return override();
    return snapshot;
  }
}

Restaurant _restaurant(int id, String name) => Restaurant(
  id: id,
  name: name,
  category: 'Chinese',
  address: '1 Jalan Test',
  phone: '0123456789',
  website: '',
  openingHours: const <OpeningHour>[],
);

void main() {
  // The cache is STATIC - shared by every facade instance - so each test must
  // start from a clean slate or a previous test's rows leak into this one.
  setUp(RestaurantRepository.invalidate);

  group('restaurant catalogue cache', () {
    test('first read downloads and populates the cache', () async {
      final _FakeCatalogueRestaurantRepository repository =
          _FakeCatalogueRestaurantRepository(DateTime(2026, 9, 10, 12));
      repository.rows = <Restaurant>[_restaurant(1, 'A')];

      final List<Restaurant> result = await repository.getRestaurants();

      expect(repository.fetchCount, 1);
      expect(result.single.name, 'A');
    });

    test('a second read inside the TTL is served from the cache', () async {
      final _FakeCatalogueRestaurantRepository repository =
          _FakeCatalogueRestaurantRepository(DateTime(2026, 9, 10, 12));
      repository.rows = <Restaurant>[_restaurant(1, 'A')];

      final List<Restaurant> first = await repository.getRestaurants();
      final List<Restaurant> second = await repository.getRestaurants();

      expect(repository.fetchCount, 1, reason: 'second read must not download');
      expect(
        identical(first, second),
        isTrue,
        reason: 'cache should hand back the same stored list',
      );
    });

    test('an expired cache downloads again on the next read', () async {
      final _FakeCatalogueRestaurantRepository repository =
          _FakeCatalogueRestaurantRepository(DateTime(2026, 9, 10, 12));
      repository.rows = <Restaurant>[_restaurant(1, 'A')];

      await repository.getRestaurants();
      expect(repository.fetchCount, 1);

      // Database changes after the first download.
      repository.rows = <Restaurant>[_restaurant(2, 'B')];

      // Age past the 5-minute TTL.
      repository.advance(const Duration(minutes: 5, seconds: 1));

      final List<Restaurant> result = await repository.getRestaurants();

      expect(
        repository.fetchCount,
        2,
        reason: 'expired cache must re-download',
      );
      expect(result.single.name, 'B');
    });

    test('a read just before the TTL boundary stays cached', () async {
      final _FakeCatalogueRestaurantRepository repository =
          _FakeCatalogueRestaurantRepository(DateTime(2026, 9, 10, 12));
      repository.rows = <Restaurant>[_restaurant(1, 'A')];

      await repository.getRestaurants();
      repository.advance(const Duration(minutes: 4, seconds: 59));

      await repository.getRestaurants();

      expect(
        repository.fetchCount,
        1,
        reason: 'a 4m59s-old cache is still fresh',
      );
    });

    test('invalidate drops the cache so the next read re-downloads', () async {
      final _FakeCatalogueRestaurantRepository repository =
          _FakeCatalogueRestaurantRepository(DateTime(2026, 9, 10, 12));
      repository.rows = <Restaurant>[_restaurant(1, 'A')];

      await repository.getRestaurants();
      expect(repository.fetchCount, 1);

      // Simulate a write (moderation, closure, hours edit...).
      repository.rows = <Restaurant>[_restaurant(3, 'C')];
      RestaurantRepository.invalidate();

      final List<Restaurant> result = await repository.getRestaurants();

      expect(
        repository.fetchCount,
        2,
        reason: 'invalidate must force a fresh download',
      );
      expect(result.single.name, 'C');
    });

    test('a new instance shares the same static cache', () async {
      final _FakeCatalogueRestaurantRepository first =
          _FakeCatalogueRestaurantRepository(DateTime(2026, 9, 10, 12));
      first.rows = <Restaurant>[_restaurant(1, 'A')];
      await first.getRestaurants();

      // A second facade-level instance (Quick Mode and Matches each build
      // their own repository) must hit the SAME cache, not re-download.
      final _FakeCatalogueRestaurantRepository second =
          _FakeCatalogueRestaurantRepository(DateTime(2026, 9, 10, 12));
      second.rows = <Restaurant>[_restaurant(99, 'should-not-be-used')];

      final List<Restaurant> result = await second.getRestaurants();

      expect(
        second.fetchCount,
        0,
        reason: 'shared static cache must serve the second instance',
      );
      expect(result.single.name, 'A');
    });

    test('concurrent cold callers share one in-flight download', () async {
      final _FakeCatalogueRestaurantRepository repository =
          _FakeCatalogueRestaurantRepository(DateTime(2026, 9, 10, 12));
      repository.rows = <Restaurant>[_restaurant(1, 'A')];
      final Completer<void> gate = Completer<void>();
      repository.downloadGate = gate;

      // Both call while the first download is still in flight.
      final Future<List<Restaurant>> callerA = repository.getRestaurants();
      final Future<List<Restaurant>> callerB = repository.getRestaurants();
      expect(
        repository.fetchCount,
        1,
        reason: 'second caller must reuse the in-flight request',
      );

      gate.complete();
      final List<Restaurant> resultA = await callerA;
      final List<Restaurant> resultB = await callerB;

      expect(repository.fetchCount, 1);
      expect(identical(resultA, resultB), isTrue);
    });

    test('a download already in flight when invalidate runs cannot repopulate '
        'the cache with pre-write rows', () async {
      final _FakeCatalogueRestaurantRepository repository =
          _FakeCatalogueRestaurantRepository(DateTime(2026, 9, 10, 12));
      repository.rows = <Restaurant>[_restaurant(1, 'A')];
      final Completer<void> gate = Completer<void>();
      repository.downloadGate = gate;

      // Start a download and hold it in flight...
      final Future<List<Restaurant>> inFlight = repository.getRestaurants();

      // ...a write lands while it is out (invalidate is called)...
      repository.rows = <Restaurant>[_restaurant(2, 'B')];
      RestaurantRepository.invalidate();

      // ...and the OLD (pre-write) download finally returns.
      gate.complete();
      final List<Restaurant> stale = await inFlight;
      expect(
        stale.single.name,
        'A',
        reason: 'the caller still gets its own request result',
      );

      // But it must NOT have filled the cache: the next read is a fresh
      // download, not a stale cache hit.
      expect(repository.fetchCount, 1);
      final List<Restaurant> fresh = await repository.getRestaurants();
      expect(
        repository.fetchCount,
        2,
        reason: 'stale in-flight result must not be cached',
      );
      expect(fresh.single.name, 'B');
    });

    test('a failed download does not poison the cache', () async {
      final _FakeCatalogueRestaurantRepository repository =
          _FakeCatalogueRestaurantRepository(DateTime(2026, 9, 10, 12));
      repository.fetchOverride = () async {
        throw Exception('network down');
      };

      await expectLater(repository.getRestaurants(), throwsA(isA<Exception>()));

      // After the failure the cache stays empty: a retry downloads again
      // rather than returning nothing-as-success.
      repository.fetchOverride = null;
      repository.rows = <Restaurant>[_restaurant(1, 'A')];
      final List<Restaurant> retry = await repository.getRestaurants();
      expect(retry.single.name, 'A');
    });
  });
}
