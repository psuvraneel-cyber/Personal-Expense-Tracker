/// Represents the available notification categories in the app.
enum NotificationCategory {
  budget(
    'budget',
    'Budget Alerts',
    'Notify when category budget limits (90%, 100%) are reached',
  ),
  anomaly(
    'anomaly',
    'Spending Anomalies',
    'Notify on unusual category spending spikes',
  ),
  bill(
    'bill',
    'Bill Reminders',
    'Notify 3 days before upcoming bill due dates',
  ),
  dailySummary(
    'dailySummary',
    'Daily Summary',
    'Daily summary of expenses and budget progress',
  ),
  weeklyReport(
    'weeklyReport',
    'Weekly Report',
    'Weekly financial insights and report summaries',
  ),
  goalProgress(
    'goalProgress',
    'Goal Milestones',
    'Updates when savings goals reach milestone thresholds',
  ),
  cashflow(
    'cashflow',
    'Cash Flow Alerts',
    'Alerts on low cash flow or balance drops',
  );

  final String key;
  final String label;
  final String description;

  const NotificationCategory(this.key, this.label, this.description);
}
