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
import android.util.Log
import io.flutter.plugin.common.EventChannel
import org.json.JSONArray
import org.json.JSONObject

/**
 * Optional NotificationListenerService for capturing UPI app notifications.
 *
 * ## Why this exists
 * Some UPI apps (Google Pay, PhonePe, Paytm) send transaction confirmations
 * as push notifications rather than SMS. This service captures those
 * notifications and forwards them to the Dart parser.
 *
 * ## How it works
 * 1. User grants Notification Access permission in system settings.
 * 2. Android calls [onNotificationPosted] for every new notification.
 * 3. We filter for known UPI/bank app packages.
 * 4. Extract notification title + text and forward to Dart via EventChannel.
 *
 * ## Play Store Compliance
 * NotificationListenerService requires BIND_NOTIFICATION_LISTENER_SERVICE
 * permission and explicit user consent (system settings toggle).
 * This is less sensitive than READ_SMS but still requires justification
 * in the Play Console declaration.
 *
 * ## Privacy
 * - Only notifications from whitelisted financial app packages are captured.
 * - No notification content is sent to any server.
 * - All processing is on-device.
 *
 * ## Integration
 * 1. Add to AndroidManifest.xml:
 *    <service
 *        android:name=".TransactionNotificationListener"
 *        android:exported="true"
 *        android:permission="android.permission.BIND_NOTIFICATION_LISTENER_SERVICE">
 *        <intent-filter>
 *            <action android:name="android.service.notification.NotificationListenerService" />
 *        </intent-filter>
 *    </service>
 *
 * 2. Request permission: TransactionNotificationListener.requestAccess(context)
 * 3. Check permission: TransactionNotificationListener.hasAccess(context)
 */
class TransactionNotificationListener : NotificationListenerService() {

    companion object {
        private const val TAG = "PET-NotifListener"

        /**
         * EventSink to forward notification data to Dart.
         * Set by the FlutterPlugin when the EventChannel is opened.
         */
        @Volatile
        var eventSink: EventChannel.EventSink? = null

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
        // This prevents promotional push notifications ("Get ₹100 cashback!")
        // from being forwarded while still catching real txn confirmations.
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

        // CRITICAL-1: Log event occurrence ONLY — NEVER interpolate body, amount, or merchant details.
        SafeLog.d(TAG, "Financial notification captured from $packageName")

        // Forward to Dart
        val data = mapOf(
            "source" to "notification",
            "package" to packageName,
            "title" to title,
            "body" to body,
            "date" to System.currentTimeMillis(),
            "type" to 1  // Treat as inbox-type
        )

        try {
            val sink = eventSink
            if (sink != null) {
                Handler(Looper.getMainLooper()).post {
                    try {
                        sink.success(data)
                    } catch (e: Exception) {
                        SafeLog.e(TAG, "Failed to deliver notification to EventSink: ${e.message}")
                        saveNotificationToCache(applicationContext ?: this, data)
                    }
                }
            } else {
                SafeLog.d(TAG, "eventSink is null, caching notification")
                saveNotificationToCache(applicationContext ?: this, data)
            }
        } catch (e: Exception) {
            SafeLog.e(TAG, "Error forwarding notification: ${e.message}")
            saveNotificationToCache(applicationContext ?: this, data)
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
