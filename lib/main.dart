import 'dart:async';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/config/env.dart';
import 'external/supabase/supabase_service.dart';
import 'model/background_process/location_monitor.dart';
import 'model/background_process/restaurant_monitor.dart';

/// Application entry point.
///
/// There is no dependency container to build: every class creates what it needs
/// itself, and the shared clients are singletons. All `main` does is load
/// configuration, open the backend connection, and start the app.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Env.load();
  await SupabaseService.initialise();

  runApp(const RasaRouteApp());

  // Background processes - stream GPS fixes to any ViewModel that listens
  // (e.g. AddLandmarkView's location picker).
  unawaited(LocationMonitor().start());

  // Watches for landmarks other tourists submit, so the dashboard can offer to
  // refresh instead of quietly going stale.
  unawaited(RestaurantMonitor().start());
}
