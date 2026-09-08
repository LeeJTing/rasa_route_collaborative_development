import '../domain_model/tourist_location.dart';
import 'dashboard_view_model.dart';

/// VIEWMODEL FACADE (inbound).
///
/// The logic and repository facades let a caller reach *down* into many
/// components through one object. This one is the mirror image: it lets a
/// background process push *up* into many ViewModels through one object.
///
/// The flow is fixed, and it runs one way only:
///
/// ```text
/// LocationMonitor  ->  CurrentLocationFacade.publish()
///                        -> DashboardViewModel.onCurrentLocationChanged()   [static]
///                        -> every registered CurrentLocationListener
/// ```
///
/// `LocationMonitor` knows this facade and nothing above it; the facade knows
/// the ViewModels. A user-requested fresh fix may also be published by the
/// dashboard before a location-dependent route is opened. No background
/// process ever holds a ViewModel reference directly.
///
/// **Two ways up, on purpose.**
///
///   * **The static entry point.** A ViewModel exposes a `static` field for the
///     latest fix and a `static` method the facade calls. That way the value
///     survives the ViewModel being disposed and rebuilt - a tourist switching
///     tabs and coming back sees the last known position immediately instead of
///     a blank map waiting on the next GPS tick. `DashboardViewModel` works
///     this way.
///   * **The listener list.** The original arrangement, still used by
///     `AddLandmarkViewModel` and `RestaurantRecommendationViewModel`. A
///     ViewModel implements [CurrentLocationListener], registers in `onInit`
///     and unregisters in `dispose` - forgetting the second leaks it.
///
/// A singleton - `CurrentLocationFacade()` always returns the same instance, so
/// the monitor and the ViewModels meet on the same object without anyone
/// passing it around.
///
/// Rules:
///   * callbacks must be cheap and must not throw;
///   * a background process never holds a ViewModel reference directly.
class CurrentLocationFacade {
  factory CurrentLocationFacade() => _instance;

  CurrentLocationFacade._();

  static final CurrentLocationFacade _instance = CurrentLocationFacade._();

  final List<CurrentLocationListener> _listeners = <CurrentLocationListener>[];

  TouristLocation _latest = TouristLocation.unknown;

  /// Most recent fix, so a ViewModel registering late is not left blank.
  TouristLocation get latest => _latest;

  void register(CurrentLocationListener listener, {bool replayLatest = true}) {
    if (_listeners.contains(listener)) return;
    _listeners.add(listener);
    if (replayLatest && _latest.isKnown) {
      listener.onCurrentLocationChanged(_latest);
    }
  }

  void unregister(CurrentLocationListener listener) =>
      _listeners.remove(listener);

  /// Publishes the latest authoritative fix. Normally called by
  /// `LocationMonitor`; the dashboard also calls it after an explicit Find Me
  /// or Quick Mode request so the destination route receives that same fix.
  void publish(TouristLocation location) {
    _latest = location;

    // Static entry points first - these hold the value whether or not a
    // ViewModel instance happens to be alive right now.
    try {
      DashboardViewModel.onCurrentLocationChanged(location);
    } catch (_) {
      // One broken ViewModel must not stop the others from updating.
    }

    for (final CurrentLocationListener listener
        in List<CurrentLocationListener>.of(_listeners)) {
      try {
        listener.onCurrentLocationChanged(location);
      } catch (_) {
        // A broken listener must not stop the others from updating.
      }
    }
  }
}

/// Implemented by any ViewModel that cares where the tourist is and has not
/// moved to a static entry point.
abstract interface class CurrentLocationListener {
  void onCurrentLocationChanged(TouristLocation location);
}
