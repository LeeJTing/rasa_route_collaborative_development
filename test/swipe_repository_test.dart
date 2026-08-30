import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/swipe_session.dart';
import 'package:rasa_route_collaborative_development/model/repositories/swipe_repository.dart';
import 'package:rasa_route_collaborative_development/shared_client/local_storage_manager/local_storage_manager.dart';

void main() {
  group('SwipeRepository', () {
    setUp(() async {
      await LocalStorageManager().clear();
    });

    test('restores a session through a new repository instance', () async {
      const SwipeSession session = SwipeSession(
        sessionId: 'session-a',
        touristId: 'tourist-a',
        stateCode: 'PNG',
        candidateFoodIds: <int>[1, 2],
        likedFoodIds: <int>[1],
        dislikedFoodIds: <int>[2],
        currentIndex: 1,
      );

      await SwipeRepository().saveSession(session);
      final SwipeSession? restored = await SwipeRepository().getSession(
        touristId: 'tourist-a',
        stateCode: 'PNG',
      );

      expect(restored?.sessionId, session.sessionId);
      expect(restored?.likedFoodIds, session.likedFoodIds);
      expect(restored?.dislikedFoodIds, session.dislikedFoodIds);
      expect(restored?.currentIndex, session.currentIndex);
    });

    test('isolates sessions by tourist and Malaysian state', () async {
      const SwipeSession penangA = SwipeSession(
        sessionId: 'penang-a',
        touristId: 'tourist-a',
        stateCode: 'PNG',
        candidateFoodIds: <int>[1],
        likedFoodIds: <int>[1],
        dislikedFoodIds: <int>[],
      );
      const SwipeSession klA = SwipeSession(
        sessionId: 'kl-a',
        touristId: 'tourist-a',
        stateCode: 'KUL',
        candidateFoodIds: <int>[2],
        likedFoodIds: <int>[2],
        dislikedFoodIds: <int>[],
      );
      const SwipeSession penangB = SwipeSession(
        sessionId: 'penang-b',
        touristId: 'tourist-b',
        stateCode: 'PNG',
        candidateFoodIds: <int>[3],
        likedFoodIds: <int>[3],
        dislikedFoodIds: <int>[],
      );
      final SwipeRepository repository = SwipeRepository();

      await repository.saveSession(penangA);
      await repository.saveSession(klA);
      await repository.saveSession(penangB);

      expect(
        (await repository.getSession(
          touristId: 'tourist-a',
          stateCode: 'PNG',
        ))?.sessionId,
        'penang-a',
      );
      expect(
        (await repository.getSession(
          touristId: 'tourist-a',
          stateCode: 'KUL',
        ))?.sessionId,
        'kl-a',
      );
      expect(
        (await repository.getSession(
          touristId: 'tourist-b',
          stateCode: 'PNG',
        ))?.sessionId,
        'penang-b',
      );
      expect(
        await repository.getSession(touristId: 'tourist-b', stateCode: 'KUL'),
        isNull,
      );
    });
  });
}
