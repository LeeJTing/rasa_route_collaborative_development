import 'package:rasa_route_collaborative_development/app/config/env.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Wrapper around the Supabase SDK.
///
/// External services are the only place a third-party SDK is imported. Nothing
/// above `APIManager` may touch this class.
///
/// A singleton: `SupabaseService()` always returns the same instance, so the
/// connection is shared without anyone having to pass it around.
class SupabaseService {
  factory SupabaseService() => _instance;

  SupabaseService._();

  static final SupabaseService _instance = SupabaseService._();

  static Future<void> initialise() async {

    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabasePublishableKey,
    );
  }
}
