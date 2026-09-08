/// Centralized calendar and week-period utility functions for P.E.T.
///
/// Ensures uniform Monday-to-Sunday weekly boundaries and day labelling
/// across Weekly Planner, Cashflow, and Alerts.
class CalendarUtils {
  CalendarUtils._();

  static const List<String> weekdayShortLabels = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];

  /// Returns the Monday 00:00:00.000 of the week containing [date].
  static DateTime getWeekStart(DateTime date) {
    final daysFromMonday = date.weekday - DateTime.monday;
    final monday = date.subtract(Duration(days: daysFromMonday));
    return DateTime(monday.year, monday.month, monday.day);
  }

  /// Returns the Sunday 23:59:59.999 of the week containing [date].
  static DateTime getWeekEnd(DateTime date) {
    final start = getWeekStart(date);
    final sunday = start.add(const Duration(days: 6));
    return DateTime(sunday.year, sunday.month, sunday.day, 23, 59, 59, 999);
  }

  /// Returns all 7 days (Monday through Sunday) for the week containing [reference].
  static List<DateTime> getWeekDays(DateTime reference) {
    final start = getWeekStart(reference);
    return List.generate(7, (i) => start.add(Duration(days: i)));
  }

  /// Checks if [a] and [b] belong to the same Monday-Sunday week.
  static bool isSameWeek(DateTime a, DateTime b) {
    final startA = getWeekStart(a);
    final startB = getWeekStart(b);
    return startA.year == startB.year &&
        startA.month == startB.month &&
        startA.day == startB.day;
  }

  /// Returns short day label ('Mon', 'Tue', etc.) for [date].
  static String formatWeekday(DateTime date) {
    return weekdayShortLabels[date.weekday - 1];
  }

  /// Stable period key for weekly limits, e.g. "2026-03-09" (Monday date).
  static String weekKey(DateTime date) {
    final start = getWeekStart(date);
    final y = start.year.toString().padLeft(4, '0');
    final m = start.month.toString().padLeft(2, '0');
    final d = start.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Convenience aliases matching domain terms
  static DateTime startOfWeek(DateTime date) => getWeekStart(date);
  static DateTime endOfWeek(DateTime date) => getWeekEnd(date);
  static String weekPeriodKey(DateTime date) => weekKey(date);
  static String weekdayShortLabel(DateTime date) => formatWeekday(date);
}
