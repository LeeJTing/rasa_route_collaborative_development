import '../../core/json_model.dart';

/// Wire shape of `public.tourist`.
///
/// Data models mirror the database **exactly**: same field names (camelCased),
/// same nullability, no computed values, no behaviour. Anything richer belongs
/// in `lib/domain_model/`.
class TouristDataModel implements JsonModel {
  const TouristDataModel({
    required this.touristId,
    required this.authUserId,
    this.email,
    this.displayName,
  });

  /// `tourist.tourist_id` (uuid, PK).
  final String touristId;

  /// `tourist.id` (uuid) -> `auth.users.id`.
  final String authUserId;

  /// Not a column - copied from the Supabase auth session when present.
  final String? email;

  /// Not a column - copied from `auth.users.user_metadata.display_name`.
  final String? displayName;

  factory TouristDataModel.fromJson(Map<String, dynamic> json) {
    return TouristDataModel(
      touristId: JsonReader.asString(json['tourist_id']),
      authUserId: JsonReader.asString(json['id']),
      email: JsonReader.asStringOrNull(json['email']),
      displayName: JsonReader.asStringOrNull(json['display_name']),
    );
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'tourist_id': touristId,
    'id': authUserId,
    'email': email,
    'display_name': displayName,
  };

  TouristDataModel copyWith({
    String? touristId,
    String? authUserId,
    String? email,
    String? displayName,
  }) {
    return TouristDataModel(
      touristId: touristId ?? this.touristId,
      authUserId: authUserId ?? this.authUserId,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
    );
  }
}
