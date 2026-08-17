import 'dietary_restriction.dart';

/// A local dish - the central entity of Rasa Route.
///
/// Domain models are plain data types. They carry no JSON - serialisation is
/// the data model's job in `lib/model/data_models/`, and the repository is what
/// converts a data model into one of these. They travel upward unchanged from
/// repository to logic to ViewModel to View.
class LocalFood {
  const LocalFood({
    required this.id,
    required this.name,
    required this.description,
    required this.origin,
    required this.culturalBackground,
    required this.ingredients,
    required this.category,
    required this.cookingStyle,
    required this.mealType,
    required this.pronunciationText,
    this.audioGuideUrl,
    required this.synonyms,
    required this.imageUrls,
    required this.dietaryRestrictions,
    required this.isFavourite,
  });

  final int id;
  final String name;
  final String description;
  final String origin;
  final String culturalBackground;
  final List<String> ingredients;
  final String category;
  final String cookingStyle;
  final String mealType;
  final String pronunciationText;
  final String? audioGuideUrl;
  final List<String> synonyms;
  final List<String> imageUrls;
  final List<DietaryRestriction> dietaryRestrictions;
  final bool isFavourite;
}
