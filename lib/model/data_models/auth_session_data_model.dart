import '../../core/json_model.dart';

/// Authentication session wire model.
///
/// Supabase SDK objects never leave the external layer. The external
/// SupabaseService extracts the SDK response into a Map`<String, dynamic>`,
/// which this data model parses.
///
/// JSON serialisation lives here; the domain model remains plain data.
class AuthSessionDataModel implements JsonModel {
  const AuthSessionDataModel({
    required this.accessToken,
    required this.refreshToken,
    required this.userId,
    required this.email,
    this.expiresAt,
  });

  final String accessToken;
  final String refreshToken;
  final String userId;
  final String email;
  final DateTime? expiresAt;

  factory AuthSessionDataModel.fromJson(Map<String, dynamic> json) {
    return AuthSessionDataModel(
      accessToken: JsonReader.asString(json['access_token']),
      refreshToken: JsonReader.asString(json['refresh_token']),
      userId: JsonReader.asString(json['user_id']),
      email: JsonReader.asString(json['email']),
      expiresAt: JsonReader.asDateOrNull(json['expires_at']),
    );
  }

  @override
  Map<String, dynamic> toJson() => <String, dynamic>{
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'user_id': userId,
    'email': email,
    'expires_at': expiresAt?.toIso8601String(),
  };
}