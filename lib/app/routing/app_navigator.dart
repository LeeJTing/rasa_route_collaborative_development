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
  static Future<T?> push<T>(String routeName) =>
      _navigator.pushNamed<T>(routeName);

  /// Replace the current route - login to shell, for example.
  static Future<T?> replaceWith<T>(String routeName) =>
      _navigator.pushReplacementNamed<T, void>(routeName);

  /// Clear the whole stack and land on [routeName] - logout, for example.
  static Future<T?> resetTo<T>(String routeName) => _navigator
      .pushNamedAndRemoveUntil<T>(routeName, (Route<dynamic> route) => false);

  /// Pop the top route, optionally returning [result].
  static void pop<T>([T? result]) {
    if (_navigator.canPop()) _navigator.pop<T>(result);
  }

  static bool get canPop => navigatorKey.currentState?.canPop() ?? false;
}
