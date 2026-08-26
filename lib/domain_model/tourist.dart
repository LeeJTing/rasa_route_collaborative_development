import 'dietary_restriction.dart';
import 'food_preference.dart';

/// The signed-in tourist.
///
/// Domain models are plain data types. They carry no JSON - serialisation is
/// the data model's job in `lib/model/data_models/`, and the repository is what
/// converts a data model into one of these. They travel upward unchanged from
/// repository to logic to ViewModel to View.
class Tourist {
  const Tourist({
    required this.touristId,
    required this.authUserId,
    required this.email,
    required this.displayName,
    this.foodPreference,
    required this.dietaryRestrictions,
  });

  final String touristId;
  final String authUserId;
  final String email;
  final String displayName;
  final FoodPreference? foodPreference;
  final List<DietaryRestriction> dietaryRestrictions;
}
