import 'dietary_restriction.dart';
import 'food_preference.dart';

/// The signed-in tourist.
///
/// Domain models are plain data types. They carry no JSON - serialisation is
/// the data model's job in `lib/model/data_models/`, and the repository is what
/// converts a data model into one of these. They travel upward unchanged from
/// repository to logic to ViewModel to View.
///
/// Both profile fields are lists for the same reason: each links the tourist
/// to many values through a junction table, so "none" is naturally the empty
/// list.
///   * [foodPreferences] - one per selected taste/category (`food_preference`
///     rows via the `personalised_preference` junction).
///   * [dietaryRestrictions] - one per held restriction (`dietary_restriction`
///     rows via the `user_dietary_restriction` junction).
///
/// Identity (tourist_id, auth id, email, display name) is created at sign-in
/// by `AuthRepository`; both lists are filled later by
/// `TouristProfileRepository` and default to empty so auth never has to know
/// about them.
class Tourist {
  const Tourist({
    required this.touristId,
    required this.authUserId,
    required this.email,
    required this.displayName,
    this.foodPreferences = const <FoodPreference>[],
    this.dietaryRestrictions = const <DietaryRestriction>[],
  });

  /// `tourist.tourist_id` - the app-facing id used as the `tourist_id` FK on
  /// every junction table (`favourite_food`, `user_dietary_restriction`,
  /// `personalised_preference`, `landmark_item`, ...).
  final String touristId;

  /// `tourist.id` -> `auth.users.id`.
  final String authUserId;

  /// From the auth session, not the `tourist` table.
  final String email;

  /// From `auth.users.user_metadata`, not the `tourist` table.
  final String displayName;

  /// The tastes and categories the tourist selected; empty when none.
  final List<FoodPreference> foodPreferences;

  /// Every dietary restriction the tourist holds; empty when none.
  final List<DietaryRestriction> dietaryRestrictions;
}
