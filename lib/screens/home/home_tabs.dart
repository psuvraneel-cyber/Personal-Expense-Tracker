import 'package:flutter/foundation.dart';

/// Lets a tab ask the home shell to switch tabs (e.g. Home's "See all"
/// opening History) without importing the shell.
abstract final class HomeTabs {
  static const int home = 0;
  static const int history = 1;
  static const int budget = 2;
  static const int settings = 3;

  /// The tab most recently asked for; the shell listens and switches.
  static final ValueNotifier<int?> request = ValueNotifier<int?>(null);

  static void show(int tab) {
    // Re-notify even if the same tab is asked for twice in a row.
    request.value = null;
    request.value = tab;
  }
}
