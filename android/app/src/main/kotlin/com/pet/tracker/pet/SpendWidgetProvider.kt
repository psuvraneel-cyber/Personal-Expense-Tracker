package com.pet.tracker.pet

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider
import java.text.NumberFormat
import java.time.LocalDate
import java.util.Locale

/**
 * Home-screen widget: what you've spent today and what's left to spend
 * today within this month's budgets.
 *
 * The app writes raw numbers (see lib/services/home_widget_service.dart);
 * the day-dependent parts are worked out here so the widget stays correct
 * after midnight even if the app hasn't run. When the app's biometric lock
 * is on, amounts are hidden.
 */
class SpendWidgetProvider : HomeWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        val state = SpendWidgetState.from(
            date = widgetData.getString(KEY_DATE, null),
            spentToday = widgetData.getString(KEY_SPENT_TODAY, null),
            monthBudgetLeft = widgetData.getString(KEY_MONTH_BUDGET_LEFT, null),
            locked = widgetData.getString(KEY_LOCKED, null) == "true",
            today = LocalDate.now(),
        )
        val money = NumberFormat.getCurrencyInstance(Locale("en", "IN")).apply {
            maximumFractionDigits = 0
        }

        for (id in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.spend_widget)
            views.setOnClickPendingIntent(
                R.id.widget_root,
                HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
            )
            when {
                state.locked -> {
                    views.setTextViewText(R.id.widget_amount, "🔒")
                    views.setTextViewText(
                        R.id.widget_label, context.getString(R.string.widget_locked),
                    )
                    views.setViewVisibility(R.id.widget_budget, View.GONE)
                }
                !state.hasData -> {
                    views.setTextViewText(R.id.widget_amount, "—")
                    views.setTextViewText(
                        R.id.widget_label, context.getString(R.string.widget_open_app),
                    )
                    views.setViewVisibility(R.id.widget_budget, View.GONE)
                }
                else -> {
                    views.setTextViewText(R.id.widget_amount, money.format(state.spentToday))
                    views.setTextViewText(
                        R.id.widget_label, context.getString(R.string.widget_spent_today),
                    )
                    views.setViewVisibility(R.id.widget_budget, View.VISIBLE)
                    views.setTextViewText(
                        R.id.widget_budget,
                        state.leftToday?.let {
                            context.getString(R.string.widget_left_today, money.format(it))
                        } ?: context.getString(R.string.widget_no_budget),
                    )
                }
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    companion object {
        const val KEY_DATE = "widget_date"
        const val KEY_SPENT_TODAY = "widget_spent_today"
        const val KEY_MONTH_BUDGET_LEFT = "widget_month_budget_left"
        const val KEY_LOCKED = "widget_locked"
    }
}

/** What the widget shows, derived from the stored values and today's date. */
internal data class SpendWidgetState(
    val locked: Boolean,
    val hasData: Boolean,
    val spentToday: Double,
    /** Budget left this month spread over the remaining days (incl. today). */
    val leftToday: Double?,
) {
    companion object {
        fun from(
            date: String?,
            spentToday: String?,
            monthBudgetLeft: String?,
            locked: Boolean,
            today: LocalDate,
        ): SpendWidgetState {
            val asOf = date?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
            if (locked || asOf == null) {
                return SpendWidgetState(locked, hasData = false, spentToday = 0.0, leftToday = null)
            }
            // Written on an earlier day: nothing has been spent "today" yet.
            val spent = if (asOf == today) spentToday?.toDoubleOrNull() ?: 0.0 else 0.0
            val sameMonth = asOf.year == today.year && asOf.month == today.month
            val left = if (sameMonth) monthBudgetLeft?.toDoubleOrNull() else null
            val daysLeft = today.lengthOfMonth() - today.dayOfMonth + 1
            val leftToday = left?.let { maxOf(0.0, it) / daysLeft }
            return SpendWidgetState(false, hasData = true, spentToday = spent, leftToday = leftToday)
        }
    }
}
