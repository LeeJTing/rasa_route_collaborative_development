import 'local_food.dart';
import 'restaurant.dart';
import 'swipe_session.dart';
import 'tourist_location.dart';

/// The active dashboard state and origin used to open Matches.
class MatchesRecommendationRequest {
  const MatchesRecommendationRequest({
    required this.origin,
    this.stateCode = '',
    this.stateName = '',
  });

  final TouristLocation origin;
  final String stateCode;
  final String stateName;
}

/// One real submitted-landmark recommendation owned by the Matches module.
///
/// It deliberately does not depend on the landmark module's detail screen.
class SubmittedLandmarkRecommendation {
  const SubmittedLandmarkRecommendation({
    required this.id,
    required this.name,
    required this.category,
    required this.distanceMetres,
    required this.dishes,
    this.imageUrl,
    this.price,
  });

  final int id;
  final String name;
  final String category;

  /// Straight-line distance from the tourist's device location. Infinite when
  /// a GPS fix is unavailable; the exploration map centre is never substituted.
  final double distanceMetres;

  /// Everything the landmark serves, each dish with its own price and photo -
  /// the same shape a restaurant's menu carries.
  final List<SubmittedLandmarkDish> dishes;

  final String? imageUrl;

  /// The landmark's headline price: the AVERAGE of [dishes]' known prices,
  /// so a stall with a menu reads as one number. Null while no dish has a
  /// price.
  final double? price;

  /// The dish names - what "Serves ..." and the expanded preview count list.
  List<String> get foodNames => dishes
      .map((SubmittedLandmarkDish dish) => dish.name)
      .toList(growable: false);
}

/// One dish a submitted landmark serves, as the recommendation carries it.
class SubmittedLandmarkDish {
  const SubmittedLandmarkDish({
    required this.name,
    this.price,
    this.imageUrl,
    this.ingredients,
  });

  /// The catalogue name when the dish links to one, else the recorded dish
  /// text.
  final String name;

  /// The price of THIS dish at the landmark, when one was recorded.
  final double? price;

  /// The dish's own photo, when it has one.
  final String? imageUrl;

  /// The dish's ingredients text (`landmark_item.ingredients`), when the
  /// record has it - the expanded rows show it like a restaurant menu row.
  final String? ingredients;
}

/// One liked local food and the real places in the active state serving it.
class MatchedFoodRecommendations {
  const MatchedFoodRecommendations({
    required this.food,
    required this.restaurants,
    required this.submittedLandmarks,
  });

  final LocalFood food;
  final List<Restaurant> restaurants;
  final List<SubmittedLandmarkRecommendation> submittedLandmarks;
}

/// State-scoped Matches result assembled from a persisted Swipe Mode session.
class MatchesRecommendationResult {
  const MatchesRecommendationResult({
    required this.stateCode,
    required this.stateName,
    required this.session,
    required this.groups,
  });

  final String stateCode;
  final String stateName;
  final SwipeSession? session;
  final List<MatchedFoodRecommendations> groups;
}
