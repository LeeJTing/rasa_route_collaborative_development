import '../core/place_category.dart';
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
    this.address = '',
    this.price,
  });

  final int id;
  final String name;

  /// The category the record carries - the RAW value, '' when it has none.
  /// What a card shows is [categoryLabel].
  final String category;

  /// Straight-line distance from the tourist's device location. Infinite when
  /// a GPS fix is unavailable; the exploration map centre is never substituted.
  final double distanceMetres;

  /// Everything the landmark serves, each dish with its own price and photo -
  /// the same shape a restaurant's menu carries.
  final List<SubmittedLandmarkDish> dishes;

  final String? imageUrl;

  /// `submitted_landmark.address` - the card shows it right under the name,
  /// exactly where a restaurant card shows the restaurant's address. Empty
  /// when the record carries none.
  final String address;

  /// The landmark's starting price: the LOWEST of [dishes]' known prices, so
  /// the card reads exactly like a restaurant's "From RM x". Null while no
  /// dish has a price.
  final double? price;

  /// The dish names - what "Serves ..." and the expanded preview count list.
  List<String> get foodNames => dishes
      .map((SubmittedLandmarkDish dish) => dish.name)
      .toList(growable: false);

  /// The category wording the cards SHOW: [placeCategoryLabel] of [category]
  /// ("Chinese" -> "Chinese Restaurant", like the restaurant catalogue's own
  /// rows), or the plain "Submitted Landmark" placeholder when the record
  /// carries no category at all. The SAME rule every other landmark surface
  /// uses, so Quick Mode and Matches read exactly like the pin sheet,
  /// Landmark History and Landmark Place Detail.
  String get categoryLabel {
    final String raw = category.trim();
    return raw.isEmpty ? 'Submitted Landmark' : placeCategoryLabel(raw);
  }
}

/// One dish a submitted landmark serves, as the recommendation carries it.
class SubmittedLandmarkDish {
  const SubmittedLandmarkDish({
    required this.name,
    this.price,
    this.imageUrl,
    this.ingredients,
    this.description,
  });

  /// The catalogue name when the dish links to one, else the recorded dish
  /// text.
  final String name;

  /// The price of THIS dish at the landmark, when one was recorded.
  final double? price;

  /// The dish's own photo, when it has one.
  final String? imageUrl;

  /// The dish's ingredients text (`landmark_item.ingredients`), when the
  /// record has it - the expanded rows show it like a restaurant menu row
  /// only when the dish carries no description.
  final String? ingredients;

  /// The dish's description (`landmark_item.description`), when the record
  /// has it - the text the expanded landmark rows show, exactly like a
  /// restaurant menu row shows its own description. Description wins;
  /// [ingredients] is only the fallback.
  final String? description;
}

/// One liked local food and the real places in the active state serving it.
class MatchedFoodRecommendations {
  const MatchedFoodRecommendations({
    required this.food,
    required this.restaurants,
    required this.submittedLandmarks,
    this.restaurantStartingPrices = const <int, double>{},
  });

  final LocalFood food;
  final List<Restaurant> restaurants;
  final List<SubmittedLandmarkRecommendation> submittedLandmarks;

  /// Lowest positive price among all active menu items at each restaurant.
  /// This is deliberately separate from [Restaurant.items], which contains
  /// only the items proving that the restaurant serves the matched food.
  final Map<int, double> restaurantStartingPrices;
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
