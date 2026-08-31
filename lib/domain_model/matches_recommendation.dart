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
    required this.foodNames,
    this.imageUrl,
    this.price,
  });

  final int id;
  final String name;
  final String category;
  final double distanceMetres;
  final List<String> foodNames;
  final String? imageUrl;
  final double? price;
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
