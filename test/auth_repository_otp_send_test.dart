import 'package:flutter_test/flutter_test.dart';
import 'package:rasa_route_collaborative_development/model/repositories/auth_repository.dart';
import 'package:rasa_route_collaborative_development/shared_client/local_storage_manager/local_storage_manager.dart';

void main() {
  final AuthRepository repository = AuthRepository();

  setUp(() async {
    // LocalStorageManager is a singleton with an in-memory cache - clear it so
    // each test starts from an empty OTP send history.
    await LocalStorageManager().clear();
  });

  group('AuthRepository OTP send history', () {
    test('recordOtpSend appends without mutating an unmodifiable list', () async {
      // Regression: `otpSendTimes` returns a fixed (unmodifiable) list and
      // `recordOtpSend` used to append in place, throwing
      // "Unsupported operation: Cannot add to an unmodifiable list" after every
      // successful send - which made every send look like a failure, never
      // recorded the send (breaking the 3-per-10 gate) and left the OTP
      // screen's resend countdown never starting (spammable button).
      await repository.recordOtpSend('tourist@example.com');
      await repository.recordOtpSend('tourist@example.com');

      final List<DateTime> times = await repository.otpSendTimes(
        'tourist@example.com',
      );
      expect(times.length, 2);
    });

    test('send history is keyed per lowercased email', () async {
      await repository.recordOtpSend('  Tourist@Example.com ');

      final List<DateTime> own = await repository.otpSendTimes(
        'tourist@example.com',
      );
      final List<DateTime> other = await repository.otpSendTimes(
        'someone@else.com',
      );

      expect(own.length, 1);
      expect(other, isEmpty);
    });

    test('old entries past one day are pruned on the next record', () async {
      // Seed a history with an entry far older than the 1-day prune window.
      final LocalStorageManager storage = LocalStorageManager();
      await repository.recordOtpSend('a@b.com');
      await storage.writeJson(
        'otp_send_history',
        <String, dynamic>{
          'a@b.com': <String>[
            DateTime.now().subtract(const Duration(days: 2)).toIso8601String(),
          ],
        },
      );

      await repository.recordOtpSend('a@b.com');

      final List<DateTime> times = await repository.otpSendTimes('a@b.com');
      expect(times.length, 1);
    });
  });
}
