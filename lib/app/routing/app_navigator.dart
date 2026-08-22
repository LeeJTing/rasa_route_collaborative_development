import 'package:flutter/material.dart';

/// Context-free navigation for ViewModels.
///
/// A ViewModel must never hold a `BuildContext`, but navigation is a
/// presentation decision. [AppNavigator] closes that gap: it owns the app's one
/// `NavigatorState` key, which `MaterialApp` picks up, so a ViewModel can move
/// screens without any widget-tree involvement.
///
/// All static - nothing to construct and nothing to pass around.
///
/// ```dart
/// AppNavigator.push(AppRoutes.foodDetail);
/// ```
abstract final class AppNavigator {
  const AppNavigator._();

  /// Attached to `MaterialApp.navigatorKey` in `app.dart`.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static NavigatorState get _navigator {
    final NavigatorState? state = navigatorKey.currentState;
    if (state == null) {
      throw StateError(
        'AppNavigator used before MaterialApp was built. Make sure '
        'MaterialApp.navigatorKey is AppNavigator.navigatorKey.',
      );
    }
    return state;
  }

  /// Push a named route on top of the stack.
  ///
  /// Deliberately does NOT call `_navigator.pushNamed<T>(routeName)`. The
  /// route registered in `app.dart`'s `MaterialApp.routes` map is always
  /// built as a `MaterialPageRoute<dynamic>` - that's how Flutter's
  /// routes-map route generator works internally, regardless of what
  /// generic argument is asked for here - so `pushNamed<T>` for any
  /// non-dynamic `T` fails an internal "is this route actually a
  /// `Route<T>`?" check with a `_CastError` before the screen even opens.
  /// This is a well-known Flutter gotcha (not specific to this app) that
  /// surfaced once a call site asked for a real typed result (a record
  /// type) instead of leaving `T` as the implicit `dynamic` every other
  /// call site happened to use.
  ///
  /// Pushing untyped and casting the *popped value* afterward avoids the
  /// route-object check entirely - a value-level cast here is always safe,
  /// since whatever popped this route already knows what type it's handing
  /// back (see e.g. `AppNavigator.pop<T>` call sites).
  static Future<T?> push<T>(String routeName) async {
    final dynamic result = await _navigator.pushNamed<dynamic>(routeName);
    return result as T?;
  }

  /// Replace the current route - login to shell, for example. Same
  /// untyped-push-then-cast fix as [push], for the same reason.
  static Future<T?> replaceWith<T>(String routeName) async {
    final dynamic result =
        await _navigator.pushReplacementNamed<dynamic, void>(routeName);
    return result as T?;
  }

  /// Clear the whole stack and land on [routeName] - logout, for example.
  /// Same untyped-push-then-cast fix as [push], for the same reason.
  static Future<T?> resetTo<T>(String routeName) async {
    final dynamic result = await _navigator.pushNamedAndRemoveUntil<dynamic>(
      routeName,
      (Route<dynamic> route) => false,
    );
    return result as T?;
  }

  /// Pop the top route, optionally returning [result].
  static void pop<T>([T? result]) {
    if (_navigator.canPop()) _navigator.pop<T>(result);
  }

  static bool get canPop => navigatorKey.currentState?.canPop() ?? false;
}
