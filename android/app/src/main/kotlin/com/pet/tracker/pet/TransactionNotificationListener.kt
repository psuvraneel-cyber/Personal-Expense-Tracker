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
 */
class TransactionNotificationListener : NotificationListenerService() {

    companion object {
        private const val TAG = "PET-NotifListener"

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
            "com.whatsapp",                              // WhatsApp Pay
            "com.whatsapp.w4b",                          // WhatsApp Business Pay

            // Major bank apps
            "com.csam.icici.bank.imobile",               // ICICI iMobile
            "com.snapwork.hdfc",                         // HDFC Mobile Banking
            "com.sbi.SBIFreedomPlus",                    // SBI YONO
            "com.axis.mobile",                           // Axis Mobile
            "com.msf.kbank.mobile",                      // Kotak 811
            "com.maborosoftware.pnb",                    // PNB ONE
            "com.bob.bobmobilebanking",                  // BOB World
            "com.canaaboroSoftware.mobilebanking",       // Canara ai1
            "com.fss.uboi",                              // Union Bank
            "com.idbibank.abhay",                        // IDBI Abhay
            "com.upi.axispay",                           // Axis Pay
            "com.infrasofttech.indianBankMobile",        // Indian Bank

            // Fintech apps
            "com.slice",                                  // Slice
            "com.jupiter.money",                          // Jupiter
            "com.epifi.paisa",                           // Fi Money
        )

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
         * Save notification data to SharedPreferences cache when the app is in background or closed.
         */
        fun saveNotificationToCache(context: Context, data: Map<String, Any?>) {
            EncryptedNotificationCache.saveNotification(context, data)
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

        if (body.isBlank()) return

        // Tighter financial check:
        // Require BOTH a currency/amount indicator AND a transaction verb.
        val hasCurrencyOrAmount = body.contains("Rs", ignoreCase = true) ||
                body.contains("INR", ignoreCase = true) ||
                body.contains("₹")

        val hasTransactionVerb = body.contains("paid", ignoreCase = true) ||
                body.contains("received", ignoreCase = true) ||
                body.contains("debited", ignoreCase = true) ||
                body.contains("credited", ignoreCase = true) ||
                body.contains("sent", ignoreCase = true) ||
                body.contains("transferred", ignoreCase = true)

        if (!hasCurrencyOrAmount || !hasTransactionVerb) return

        SafeLog.d(TAG, "Financial notification captured from $packageName")

        val data = mapOf(
            "source" to "notification",
            "package" to packageName,
            "title" to title,
            "body" to body,
            "date" to System.currentTimeMillis(),
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
