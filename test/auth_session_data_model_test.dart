import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/domain_model/auth_session.dart';
import 'package:rasa_route_collaborative_development/model/data_models/auth_session_data_model.dart';

void main() {
  group('AuthSessionDataModel', () {
    test('parses every field from a Supabase session map', () {
      const Map<String, dynamic> json = <String, dynamic>{
        'access_token': 'access-123',
        'refresh_token': 'refresh-456',
        'user_id': 'user-789',
        'email': 'tourist@example.com',
        'expires_at': '2026-09-01T00:00:00.000Z',
      };

      final AuthSessionDataModel model = AuthSessionDataModel.fromJson(json);

      expect(model.accessToken, 'access-123');
      expect(model.refreshToken, 'refresh-456');
      expect(model.userId, 'user-789');
      expect(model.email, 'tourist@example.com');
      expect(model.expiresAt, DateTime.parse('2026-09-01T00:00:00.000Z'));
    });

    test('treats missing optional fields as empty / null', () {
      final AuthSessionDataModel model = AuthSessionDataModel.fromJson(
        const <String, dynamic>{},
      );

      expect(model.accessToken, '');
      expect(model.refreshToken, '');
      expect(model.userId, '');
      expect(model.email, '');
      expect(model.expiresAt, isNull);
    });

    test('toJson round-trips through fromJson', () {
      final AuthSessionDataModel model =
          AuthSessionDataModel.fromJson(const <String, dynamic>{
            'access_token': 'a',
            'refresh_token': 'r',
            'user_id': 'u',
            'email': 'e@example.com',
            'expires_at': '2026-09-01T00:00:00.000Z',
          });

      final Map<String, dynamic> json = model.toJson();

      expect(AuthSessionDataModel.fromJson(json).toJson(), json);
    });

    test(
      'constructor emits the keys AuthRepository persists for a session',
      () {
        final AuthSession session = AuthSession(
          accessToken: 'a',
          refreshToken: 'r',
          userId: 'u',
          email: 'e@example.com',
          expiresAt: DateTime.utc(2026, 9, 1),
        );

        final Map<String, dynamic> json = AuthSessionDataModel(
          accessToken: session.accessToken,
          refreshToken: session.refreshToken,
          userId: session.userId,
          email: session.email,
          expiresAt: session.expiresAt,
        ).toJson();

        expect(json['access_token'], 'a');
        expect(json['refresh_token'], 'r');
        expect(json['user_id'], 'u');
        expect(json['email'], 'e@example.com');
        expect(json['expires_at'], '2026-09-01T00:00:00.000Z');
      },
    );
  });
}
