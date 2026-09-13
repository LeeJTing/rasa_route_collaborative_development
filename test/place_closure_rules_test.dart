import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/place_closure_rules.dart';

/// The read-time availability rule the landmark/restaurant reads share: a
/// place frozen by a TEMPORARY closure becomes available again once its
/// `closed_until` passes, and that read writes the change back.
void main() {
  final DateTime now = DateTime.utc(2026, 9, 14);

  test('available is effectively available, nothing to write back', () {
    expect(
      PlaceClosureRules.isEffectivelyAvailable(status: 'available', now: now),
      isTrue,
    );
    expect(
      PlaceClosureRules.needsReactivation(status: 'available', now: now),
      isFalse,
    );
  });

  test('a frozen place is hidden until its closure window passes', () {
    expect(
      PlaceClosureRules.isEffectivelyAvailable(
        status: 'frozen',
        closedUntil: now.add(const Duration(days: 1)),
        now: now,
      ),
      isFalse,
    );
    expect(
      PlaceClosureRules.isEffectivelyAvailable(
        status: 'frozen',
        closedUntil: now.subtract(const Duration(minutes: 1)),
        now: now,
      ),
      isTrue,
    );
  });

  test('an expired closure asks for the write-back, a live one does not', () {
    expect(
      PlaceClosureRules.needsReactivation(
        status: 'frozen',
        closedUntil: now.subtract(const Duration(days: 1)),
        now: now,
      ),
      isTrue,
    );
    expect(
      PlaceClosureRules.needsReactivation(
        status: 'frozen',
        closedUntil: now.add(const Duration(days: 1)),
        now: now,
      ),
      isFalse,
    );
    // A permanent freeze carries no closed_until - never auto-reactivated.
    expect(
      PlaceClosureRules.needsReactivation(status: 'frozen', now: now),
      isFalse,
    );
  });

  test('blank/legacy and removed statuses stay hidden', () {
    expect(
      PlaceClosureRules.isEffectivelyAvailable(status: '', now: now),
      isFalse,
    );
    expect(
      PlaceClosureRules.isEffectivelyAvailable(status: null, now: now),
      isFalse,
    );
    expect(
      PlaceClosureRules.isEffectivelyAvailable(status: 'removed', now: now),
      isFalse,
    );
  });
}
