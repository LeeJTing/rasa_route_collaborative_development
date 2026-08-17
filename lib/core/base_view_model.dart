import 'package:flutter/foundation.dart';

import 'view_state.dart';

/// Base class for every ViewModel in `lib/view_models/`.
///
/// Responsibilities of a ViewModel, per the Software Architecture Diagram:
///   * hold presentation state for exactly one View;
///   * call **one** logic facade (never a repository, never Supabase/Gemini);
///   * expose plain getters the View can read;
///   * expose `void`/`Future<void>` commands the View can invoke.
///
/// A ViewModel must never import `package:flutter/material.dart`,
/// never hold a `BuildContext`, and never build a widget. Navigation is
/// requested by returning a route name (see `lib/app/routing/`) or by the View
/// reacting to state - not by pushing routes from here.
abstract class BaseViewModel extends ChangeNotifier {
  ViewState _state = ViewState.idle;
  String? _errorMessage;
  bool _disposed = false;

  ViewState get state => _state;
  String? get errorMessage => _errorMessage;

  bool get isBusy => _state.isBusy;
  bool get isReady => _state.isReady;
  bool get hasError => _state.isError;

  /// Called once by the View's `initState` (via `_ViewState.didChangeDependencies`
  /// or an explicit call). Override to load first data. Default is a no-op.
  Future<void> onInit() async {}

  /// Moves the ViewModel into [ViewState.busy] and notifies listeners.
  @protected
  void setBusy() => _setState(ViewState.busy, null);

  /// Moves the ViewModel into [ViewState.ready] and notifies listeners.
  @protected
  void setReady() => _setState(ViewState.ready, null);

  /// Moves the ViewModel into [ViewState.idle] and notifies listeners.
  @protected
  void setIdle() => _setState(ViewState.idle, null);

  /// Moves the ViewModel into [ViewState.error] with a user-facing message.
  @protected
  void setError(Object error, [StackTrace? stackTrace]) {
    if (kDebugMode) {
      debugPrint('[$runtimeType] $error\n$stackTrace');
    }
    _setState(ViewState.error, _humanise(error));
  }

  /// Runs [action] wrapped in busy/ready/error state transitions.
  ///
  /// This is the workhorse - almost every ViewModel command should be:
  /// ```dart
  /// Future<void> loadFoods() => runGuarded(() async {
  ///   _foods = await _facade.fetchLocalFoods();
  /// });
  /// ```
  @protected
  Future<void> runGuarded(
    Future<void> Function() action, {
    bool silent = false,
  }) async {
    if (!silent) setBusy();
    try {
      await action();
      if (!silent) setReady();
    } catch (error, stackTrace) {
      setError(error, stackTrace);
    }
  }

  /// Clears the error and returns to [ViewState.idle]. Wire this to "Retry".
  void clearError() {
    if (_errorMessage == null && _state != ViewState.error) return;
    _setState(ViewState.idle, null);
  }

  void _setState(ViewState next, String? message) {
    _state = next;
    _errorMessage = message;
    safeNotifyListeners();
  }

  /// `notifyListeners()` that tolerates being called after `dispose()`, which
  /// happens when an async task completes after the user leaves the screen.
  @protected
  void safeNotifyListeners() {
    if (_disposed) return;
    notifyListeners();
  }

  String _humanise(Object error) {
    final String raw = error.toString();
    return raw.startsWith('Exception: ')
        ? raw.substring('Exception: '.length)
        : raw;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
