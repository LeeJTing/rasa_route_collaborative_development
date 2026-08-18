import '../model/data_models/location_data_model.dart';

/// VIEWMODEL FACADE (inbound).
///
/// The logic and repository facades let a caller reach *down* into many
/// components through one object. This one is the mirror image: it lets a
/// background process push *up* into many ViewModels through one object.
///
/// `LocationMonitor` publishes here. Any number of ViewModels implement
/// [CurrentLocationListener] and register themselves; the monitor knows about
/// none of them.
///
/// A singleton - `CurrentLocationFacade()` always returns the same instance, so
/// the monitor and the ViewModels meet on the same object without anyone
/// passing it around.
///
/// Rules:
///   * a ViewModel registers in `onInit` and unregisters in `dispose` -
///     forgetting the second leaks the ViewModel;
///   * listener callbacks must be cheap and must not throw;
///   * a background process never holds a ViewModel reference directly.
class CurrentLocationFacade {
  factory CurrentLocationFacade() => _instance;

  CurrentLocationFacade._();

  static final CurrentLocationFacade _instance = CurrentLocationFacade._();

  final List<CurrentLocationListener> _listeners = <CurrentLocationListener>[];

  LocationDataModel _latest = LocationDataModel.unknown;

  /// Most recent fix, so a ViewModel registering late is not left blank.
  LocationDataModel get latest => _latest;

  void register(CurrentLocationListener listener) {
    if (_listeners.contains(listener)) return;
    _listeners.add(listener);
    if (_latest.isKnown) listener.onCurrentLocationChanged(_latest);
  }

  void unregister(CurrentLocationListener listener) =>
      _listeners.remove(listener);

  /// Called by `LocationMonitor`. Fans out to every registered ViewModel.
  void publish(LocationDataModel location) {
    _latest = location;
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

/// Implemented by any ViewModel that cares where the tourist is.
abstract interface class CurrentLocationListener {
  void onCurrentLocationChanged(LocationDataModel location);
}
