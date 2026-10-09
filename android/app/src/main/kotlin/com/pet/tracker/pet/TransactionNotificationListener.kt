package com.pet.tracker.pet

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import androidx.annotation.GuardedBy
import androidx.annotation.VisibleForTesting
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequest
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import dev.fluttercommunity.workmanager.BackgroundWorker
import io.flutter.plugin.common.EventChannel

/**
 * Optional NotificationListenerService for capturing UPI app notifications.
 *
 * ## Threading & Concurrency Architecture:
 * - [onNotificationPosted] runs asynchronously on background Binder IPC threads.
 * - Flutter's [EventChannel.EventSink] MUST be invoked strictly on the Android Main (UI) thread.
 * - To prevent check-then-act race conditions between background dispatching and main thread [onCancel]
 *   or listener re-creation, all sink mutations and version tokens are synchronized under [sinkLock].
 * - Event delivery uses a double-checked version token verification on the Main Thread:
 *   If the sink was cancelled or replaced while the task was enqueued on the Main Looper, the task
 *   never invokes [EventChannel.EventSink.success] on a stale sink (preventing [IllegalStateException]),
 *   and instead safely delivers to any newly active sink or persists to [EncryptedNotificationCache].
 * - When persisting to [EncryptedNotificationCache] while the app is closed / engine unattached,
 *   an expedited [OneTimeWorkRequest] is enqueued to process the notification and evaluate budget/anomaly
 *   alerts in a background Dart isolate within seconds.
 */
class TransactionNotificationListener : NotificationListenerService() {

    companion object {
        private const val TAG = "PET-NotifListener"
        const val TASK_PROCESS_NOTIFICATIONS = "com.pet.tracker.processNotifications"
        const val WORK_NAME_EXPEDITED_NOTIF = "com.pet.tracker.processNotifications.immediate"

        private val sinkLock = Any()

        @GuardedBy("sinkLock")
        private var _eventSink: EventChannel.EventSink? = null

        @GuardedBy("sinkLock")
        private var _sinkVersion: Long = 0L

        /**
         * Visible for testing: Context fallback for unattached service instances in unit tests.
         */
        @VisibleForTesting
        var listenerContext: Context? = null

        /**
         * Thread-safe property for managing EventSink subscription.
         * Setting a new sink automatically increments the session version token atomically.
         */
        var eventSink: EventChannel.EventSink?
            get() = synchronized(sinkLock) { _eventSink }
            set(value) = synchronized(sinkLock) {
                _eventSink = value
                _sinkVersion++
                SafeLog.d(TAG, "EventSink updated (version=$_sinkVersion, active=${value != null})")
            }

        /**
         * Visible for testing: Resets static synchronization state.
         */
        @VisibleForTesting
        fun resetForTesting() {
            synchronized(sinkLock) {
                _eventSink = null
                _sinkVersion = 0L
                listenerContext = null
            }
            synchronized(this) { recentKeys.clear() }
        }

        /**
         * Visible for testing: Gets current sink version token.
         */
        @VisibleForTesting
        fun getSinkVersionForTesting(): Long = synchronized(sinkLock) { _sinkVersion }

        /**
         * Whitelisted UPI/bank app package names.
         * Only notifications from these apps are captured.
         */
        val FINANCIAL_PACKAGES = setOf(
            // UPI apps
            "com.google.android.apps.nbu.paisa.user",  // Google Pay
            "com.phonepe.app",                           // PhonePe
            "net.one97.paytm",                           // Paytm
            "in.org.npci.upiapp",                        // BHIM
            "in.amazon.mShop.android.shopping",          // Amazon Pay
            // Messaging apps (e.g. WhatsApp) are deliberately excluded: their
            // notifications are personal conversations, not payment alerts.

            // Major bank apps
            "com.csam.icici.bank.imobile",               // ICICI iMobile
            "com.snapwork.hdfc",                         // HDFC Mobile Banking
            "com.sbi.SBIFreedomPlus",                    // YONO Lite SBI
            "com.sbi.lotusintouch",                      // YONO SBI
            "com.axis.mobile",                           // Axis Mobile
            "com.msf.kbank.mobile",                      // Kotak 811
            "com.Version1",                              // PNB ONE
            "com.bankofbaroda.mconnect",                 // bob World
            "com.canarabank.mobility",                   // Canara ai1
            "com.fss.uboi",                              // Union Bank
            "com.idbibank.abhay",                        // IDBI Abhay
            "com.upi.axispay",                           // Axis Pay
            "com.infrasofttech.indianBankMobile",        // Indian Bank

            // Fintech apps
            "indwin.c3.shareapp",                         // slice
            "money.jupiter",                              // Jupiter
            "com.epifi.paisa",                           // Fi Money
            "com.dreamplug.androidapp",                   // CRED
            "com.naviapp",                                // Navi
            "com.hdfcbank.payzapp",                       // PayZapp
            "money.super.payments",                       // Super.money
            "com.tatadigital.tcp",                        // Tata Neu
            "com.freecharge.android",                     // Freecharge
            "com.myairtelapp",                            // Airtel Thanks
            "com.mobikwik_new",                           // MobiKwik
        )

        /** Recently captured notifications (key + content) to drop re-posts/updates. */
        private val recentKeys = object : LinkedHashMap<String, Boolean>(64, 0.75f, true) {
            override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Boolean>?) = size > 200
        }

        /** Returns true the first time a given notification content is seen. */
        @Synchronized
        @VisibleForTesting
        fun markFirstSeen(dedupKey: String): Boolean {
            if (recentKeys.containsKey(dedupKey)) return false
            recentKeys[dedupKey] = true
            return true
        }

        /**
         * Check if notification access is granted.
         */
        fun hasAccess(context: Context): Boolean {
            val cn = ComponentName(context, TransactionNotificationListener::class.java)
            val enabledListeners = Settings.Secure.getString(
                context.contentResolver,
                "enabled_notification_listeners"
            ) ?: return false
            return enabledListeners.contains(cn.flattenToString())
        }

        /**
         * Open system settings to grant notification access.
         */
        fun requestAccess(context: Context) {
            val intent = Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
        }

        /**
         * Save notification data to SharedPreferences cache when the app is in background or closed,
         * and enqueue an expedited WorkManager request for immediate background Dart isolate execution.
         */
        fun saveNotificationToCache(context: Context, data: Map<String, Any?>) {
            EncryptedNotificationCache.saveNotification(context, data)
            enqueueExpeditedNotificationProcessing(context)
        }

        /**
         * Enqueue an expedited WorkManager one-off task to process cached notifications.
         */
        fun enqueueExpeditedNotificationProcessing(context: Context) {
            try {
                val inputData = Data.Builder()
                    .putString(BackgroundWorker.DART_TASK_KEY, TASK_PROCESS_NOTIFICATIONS)
                    .build()

                val workRequestBuilder = OneTimeWorkRequest.Builder(BackgroundWorker::class.java)
                    .setInputData(inputData)

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    workRequestBuilder.setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
                }

                val workRequest = workRequestBuilder.build()

                WorkManager.getInstance(context).enqueueUniqueWork(
                    WORK_NAME_EXPEDITED_NOTIF,
                    ExistingWorkPolicy.APPEND_OR_REPLACE, // never cancel an in-flight import
                    workRequest
                )
                SafeLog.d(TAG, "Enqueued expedited WorkManager task ($WORK_NAME_EXPEDITED_NOTIF)")
            } catch (e: Exception) {
                SafeLog.e(TAG, "Failed to enqueue expedited notification processing: ${e.message}", e)
            }
        }
    }

    private fun resolveContext(): Context? {
        return try {
            applicationContext ?: listenerContext
        } catch (e: Exception) {
            listenerContext
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return

        val packageName = sbn.packageName ?: return

        // Only process notifications from whitelisted financial apps
        if (packageName !in FINANCIAL_PACKAGES) return

        val notification = sbn.notification ?: return
        val extras = notification.extras ?: return

        val title = extras.getCharSequence("android.title")?.toString() ?: ""
        val text = extras.getCharSequence("android.text")?.toString() ?: ""
        val bigText = extras.getCharSequence("android.bigText")?.toString()

        // Use bigText if available (contains full transaction details)
        val body = bigText ?: text

        if (body.isBlank() && title.isBlank()) return

        // Combined inspection across both title and body
        val combinedText = "$title $body"

        // Require currency or amount indicator
        // Currency marker followed by a number ("₹500", "Rs. 1,200"); a bare
        // "rs" substring would match ordinary words like "hours" or "yours".
        val hasCurrencyOrAmount = SmsReaderPlugin.currencyAmountRegex.containsMatchIn(combinedText)

        // Comprehensive financial verbs to avoid false negatives
        val hasTransactionVerb = combinedText.contains("paid", ignoreCase = true) ||
                combinedText.contains("received", ignoreCase = true) ||
                combinedText.contains("debited", ignoreCase = true) ||
                combinedText.contains("credited", ignoreCase = true) ||
                combinedText.contains("sent", ignoreCase = true) ||
                combinedText.contains("transferred", ignoreCase = true) ||
                combinedText.contains("spent", ignoreCase = true) ||
                combinedText.contains("deducted", ignoreCase = true) ||
                combinedText.contains("successful", ignoreCase = true) ||
                combinedText.contains("payment", ignoreCase = true) ||
                combinedText.contains("withdrawn", ignoreCase = true) ||
                combinedText.contains("charged", ignoreCase = true) ||
                combinedText.contains("purchase", ignoreCase = true) ||
                combinedText.contains("refund", ignoreCase = true) ||
                combinedText.contains("reversed", ignoreCase = true) ||
                combinedText.contains("completed", ignoreCase = true) ||
                combinedText.contains("cashback", ignoreCase = true) ||
                combinedText.contains("added", ignoreCase = true)

        if (!hasCurrencyOrAmount || !hasTransactionVerb) return

        // Conservative native filter against obvious non-transaction noise
        val isNegativePromoOrOtp = combinedText.contains("OTP", ignoreCase = true) ||
                combinedText.contains("one time password", ignoreCase = true) ||
                combinedText.contains("use coupon", ignoreCase = true) ||
                combinedText.contains("get flat", ignoreCase = true) ||
                combinedText.contains("claim cashback offer", ignoreCase = true) ||
                combinedText.contains("apply for loan", ignoreCase = true)

        if (isNegativePromoOrOtp) return

        // Apps re-post/update the same notification (progress, grouping);
        // only the first copy of a given content is captured.
        // Same notification (key) + same `when` + same text = a re-post or
        // progress update, not a new payment. Distinct payments get distinct
        // keys or `when` values, so they are never merged here.
        val notificationKey = runCatching { sbn.key }.getOrNull()
            ?: System.identityHashCode(sbn).toString()
        val postedWhen = runCatching { notification.`when` }.getOrDefault(0L)
        if (!markFirstSeen("$notificationKey|$postedWhen|${combinedText.hashCode()}")) return

        SafeLog.d(TAG, "Financial notification captured from $packageName")

        val data = mapOf(
            "schemaVersion" to 1,
            "source" to "notification",
            "package" to packageName,
            "title" to title,
            "body" to body,
            // When the payment app posted it — stable across re-deliveries.
            "date" to (runCatching { sbn.postTime }.getOrNull()?.takeIf { it > 0 }
                ?: System.currentTimeMillis()),
            "type" to 1  // Treat as inbox-type
        )

        // Snapshot current sink & version under lock
        val (capturedSink, capturedVersion) = synchronized(sinkLock) {
            Pair(_eventSink, _sinkVersion)
        }

        val targetCtx = resolveContext()

        if (capturedSink == null) {
            SafeLog.d(TAG, "eventSink is null, caching notification")
            if (targetCtx != null) {
                saveNotificationToCache(targetCtx, data)
            }
            return
        }

        // Post to Main Thread for EventChannel delivery with version verification
        Handler(Looper.getMainLooper()).post {
            try {
                val (currentSink, currentVersion) = synchronized(sinkLock) {
                    Pair(_eventSink, _sinkVersion)
                }

                if (currentSink === capturedSink && currentVersion == capturedVersion) {
                    // Sink is 100% active, un-cancelled, and un-replaced
                    capturedSink.success(data)
                } else if (currentSink != null) {
                    // Sink was reconnected/recreated while Runnable was in Main Looper queue
                    currentSink.success(data)
                } else {
                    // Sink was cancelled (onCancel). Cache notification safely
                    SafeLog.d(TAG, "EventSink was cancelled prior to execution. Caching notification.")
                    if (targetCtx != null) {
                        saveNotificationToCache(targetCtx, data)
                    }
                }
            } catch (e: Exception) {
                SafeLog.e(TAG, "Failed to deliver notification to EventSink: ${e.message}")
                if (targetCtx != null) {
                    saveNotificationToCache(targetCtx, data)
                }
            }
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        // No action needed
    }

    override fun onListenerConnected() {
        super.onListenerConnected()
        SafeLog.d(TAG, "Notification listener connected")
    }

    override fun onListenerDisconnected() {
        super.onListenerDisconnected()
        SafeLog.d(TAG, "Notification listener disconnected")
    }
}
