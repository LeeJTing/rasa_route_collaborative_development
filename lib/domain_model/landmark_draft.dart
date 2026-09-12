import 'local_food.dart';
import 'opening_hour.dart';
import 'tourist_location.dart';

/// One saved (incomplete) Add-New-Landmark form.
///
/// A draft is what the tourist had entered when they left the form - the
/// location they stood at, the restaurant details, every food (with its
/// price and photo), the opening hours and the signboard/stall photo - so
/// the form can be resumed later, even after the app was closed. Drafts are
/// kept for 24 hours from their last save ([expiresAt]) and are deleted
/// (row + uploaded photos) after that.
///
/// Domain models are plain data types. They carry no JSON - serialisation is
/// the data model's job in `lib/model/data_models/`, and the repository is
/// what converts a data model into one of these. They travel upward
/// unchanged from repository to logic to ViewModel to View.
class LandmarkDraft {
  const LandmarkDraft({
    required this.id,
    required this.restaurantName,
    this.phone = '',
    this.website = '',
    this.address = '',
    this.category = '',
    this.restaurantConfirmed = false,
    this.baseLocation = TouristLocation.unknown,
    this.adjustedLocation = TouristLocation.unknown,
    this.landmarkPhoto,
    this.foods = const <LandmarkDraftFood>[],
    this.operatingHours = const <Weekday, List<OpeningHour>>{},
    required this.expiresAt,
    required this.updatedAt,
  });

  /// `landmark_draft.draft_id`. `0` for a draft not saved yet.
  final int id;

  /// The restaurant name typed or extracted from the signboard, `''` when
  /// the tourist had not reached that field.
  final String restaurantName;

  /// Optional contact/address fields, `''` when not provided.
  final String phone;
  final String website;
  final String address;

  /// The primary food's category - what `submitted_landmark.category` will
  /// store once the draft is submitted.
  final String category;

  /// Whether the tourist pressed Confirm under the Restaurant Name before
  /// this save - carried so a resumed submission keeps its verified state
  /// (the Confirm row reports it instead of asking again, and submission is
  /// not blocked on a confirmation that already happened).
  final bool restaurantConfirmed;

  /// Where the FIRST food was captured. This is the landmark's location
  /// while the form is open (the pin defaults here) and the reference every
  /// later capture (additional food / signboard / stall) must stay within
  /// 50 m of.
  final TouristLocation baseLocation;

  /// The pin the tourist moved by hand, if they moved it - [TouristLocation.unknown]
  /// while they left it at the captured fix.
  final TouristLocation adjustedLocation;

  /// The landmark's own signboard/stall photo, if it had been captured.
  final LandmarkDraftPhoto? landmarkPhoto;

  /// The foods on the form - the recognised primary food first, then every
  /// "Add More Food" entry, matching the order they appear on the form.
  final List<LandmarkDraftFood> foods;

  /// Every day's opening-hours rows, keyed like the form's own editor (a
  /// Closed/Unknown day holds exactly one row with null times).
  final Map<Weekday, List<OpeningHour>> operatingHours;

  /// When this draft stops being resumable - 24 hours after its last save.
  final DateTime expiresAt;

  /// When the draft was last saved.
  final DateTime updatedAt;

  /// The first food on the form, if the tourist had captured one.
  LandmarkDraftFood? get primaryFood => foods.isEmpty ? null : foods.first;

  /// The photo shown next to this draft in a list: the primary food's photo
  /// when there is one, else the landmark's signboard/stall photo.
  LandmarkDraftPhoto? get thumbnailPhoto => primaryFood?.photo ?? landmarkPhoto;

  /// Whether this draft is past its 24-hour life and must be purged.
  bool get isExpired => !DateTime.now().isBefore(expiresAt);

  /// How long this draft still has, or [Duration.zero] once expired.
  Duration get timeUntilExpiry {
    final Duration remaining = expiresAt.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Everything a submitted landmark would need from this draft - used to
  /// tell "empty" drafts (nothing worth saving) from filled ones.
  bool get hasContent =>
      foods.isNotEmpty ||
      restaurantName.trim().isNotEmpty ||
      landmarkPhoto != null;
}

/// One food saved on a draft, with the state the form was holding for it.
class LandmarkDraftFood {
  const LandmarkDraftFood({
    required this.food,
    this.price,
    this.priceMin = 0,
    this.priceMax = 0,
    this.confidence = 0,
    this.dietaryRestrictions = const <String>[],
    this.variant = '',
    this.captureLocation = TouristLocation.unknown,
    this.photo,
  });

  /// The recognised (or picked / name-typed) dish, complete enough to carry
  /// through recognition, catalogue growth and submission on resume.
  final LocalFood food;

  /// The price the tourist entered, or null when they had not entered one.
  final double? price;

  /// Gemini's suggested price range for [food]. `0` means unknown.
  final double priceMin;
  final double priceMax;

  /// Gemini's confidence in the dish name - only meaningful for the primary
  /// food (see `LandmarkDraftHandoff.pendingConfidence`).
  final double confidence;

  /// Canonical dietary-restriction names for [food], written to
  /// `food_dietary_restriction` when it becomes a new catalogue row.
  final List<String> dietaryRestrictions;

  /// The VARIANT name this food was seen/typed as when it EXTENDS the
  /// dictionary dish into an unlisted variant (`Cendol Jagung` -> `Cendol`) -
  /// restored onto the form and written to `landmark_item.variant`. Empty
  /// when the name IS the dish.
  final String variant;

  /// Where THIS food was captured - the primary food's is the landmark's
  /// location; the others were checked against it (50 m rule).
  final TouristLocation captureLocation;

  /// This food's own photo, when one was captured.
  final LandmarkDraftPhoto? photo;
}

/// A photo stored for a draft: the storage object name (`image_id`) and the
/// public URL the row would store for it.
class LandmarkDraftPhoto {
  const LandmarkDraftPhoto({
    required this.id,
    required this.url,
    this.type,
    this.captureLocation = TouristLocation.unknown,
  });

  /// The storage object name in the `landmark-images` bucket.
  final String id;

  /// The public HTTPS URL of [id].
  final String url;

  /// `'signboard'` or `'stall'` for the landmark's own photo; null for a
  /// food photo.
  final String? type;

  /// Where this photo was taken - recorded for the landmark's signboard/stall
  /// photo so a resumed form still knows its own capture spot (the food
  /// photos carry their spot on the food entry itself).
  final TouristLocation captureLocation;
}
