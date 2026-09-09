import 'package:flutter/material.dart';

/// Provides the current [ThemeMode] and a setter to any descendant widget
/// without requiring prop-drilling through the widget tree.
class ThemeModeNotifier extends InheritedWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  const ThemeModeNotifier({
    super.key,
    required this.themeMode,
    required this.onThemeModeChanged,
    required super.child,
  });

  static ThemeModeNotifier of(BuildContext context) {
    final result =
        context.dependOnInheritedWidgetOfExactType<ThemeModeNotifier>();
    assert(result != null, 'No ThemeModeNotifier found in context');
    return result!;
  }

  @override
  bool updateShouldNotify(ThemeModeNotifier oldWidget) =>
      themeMode != oldWidget.themeMode;
}
