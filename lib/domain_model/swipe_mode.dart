import 'local_food.dart';
import 'swipe_session.dart';

/// Real catalogue data and any saved state for one state's Swipe Mode deck.
class SwipeModePreparation {
  const SwipeModePreparation({
    required this.stateCode,
    required this.stateName,
    required this.touristId,
    required this.queue,
    required this.restrictedFoodIds,
    required this.savedSession,
    required this.savedRestaurantCount,
  });

  final String stateCode;
  final String stateName;
  final String touristId;
  final List<LocalFood> queue;
  final Set<int> restrictedFoodIds;
  final SwipeSession? savedSession;
  final int savedRestaurantCount;
}
