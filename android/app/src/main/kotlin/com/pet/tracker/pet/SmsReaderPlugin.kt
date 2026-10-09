package com.pet.tracker.pet

import android.content.BroadcastReceiver
import android.content.ContentResolver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Telephony
import android.telephony.SmsMessage
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import androidx.annotation.GuardedBy
import org.json.JSONArray
import org.json.JSONObject
import android.util.Log

/**
 * Native Android plugin that reads SMS directly from the system content provider
 * (content://sms) using ContentResolver.
 *
 * ## Capabilities
 * - Reads INBOX (content://sms/inbox) only — received bank transaction alerts.
 *   The user's own sent messages are never read (data minimisation).
 * - Pre-filters SMS by known bank sender patterns on native side for performance
 * - Registers BroadcastReceiver for real-time SMS_RECEIVED events
 *
 * ## Why ContentResolver?
 * The system content provider stores ALL SMS regardless of which app is the
 * default SMS handler. This works even when Google Messages, Samsung Messages,
 * or any third-party app is the default SMS application.
 */
class SmsReaderPlugin : FlutterPlugin, MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler {

    companion object {
        private const val TAG = "SmsReaderPlugin"

        private val sinkLock = Any()

        @GuardedBy("sinkLock")
        private var _eventSink: EventChannel.EventSink? = null

        /**
         * Thread-safe property for managing SMS EventSink subscription.
         */
        var eventSink: EventChannel.EventSink?
            get() = synchronized(sinkLock) { _eventSink }
            set(value) = synchronized(sinkLock) {
                _eventSink = value
                SafeLog.d(TAG, "EventSink updated (active=${value != null})")
            }

        /**
         * Known bank/UPI sender ID patterns for native-side pre-filtering.
         * Matching is case-insensitive, partial match on the sender address.
         * This avoids passing millions of personal/promo SMS to Dart.
         */
        val bankSenderPatterns = listOf(
            // Major private banks
            "HDFC", "HDFCBK", "ICICI", "ICICIB", "AXIS", "AXISBK", "KOTAK", "KOTAKB",
            "YESBK", "YESBNK", "INDUS", "INDBNK",
            "FEDER", "FEDBNK", "IDFCFB", "IDFCBK", "RBLBNK", "RBLBK",
            "BANDHN", "DBSBNK",
            // Major public banks
            "SBI", "SBIINB", "SBIPSG", "PNB", "PNBSMS", "BOB", "BARODA", "BARODAB",
            "CANARA", "CANBK", "UNION", "UNIONB", "UBOI",
            "IDBI", "IDBIBK", "INDIAN", "INDBNK", "CENTRL", "CENTBK",
            "IOB", "IOBSMS", "UCO", "UCOBK",
            "BOI", "BOIIND", "KARNAB", "KRNTKB", "SOUTHI", "SIBBNK",
            // Payments banks & UPI apps
            "PAYTM", "PYTM", "AIRTEL", "JIOFI", "JIOPA", "GPAY", "GOOGLE",
            "PHONEPE", "PHNEPE", "BHIM", "AMAZONP", "AMZNPAY", "WHATSAP",
            // Foreign banks
            "STANCHART", "SCBANK", "SCBIND", "CITI", "CITIBNK", "HSBC", "HSBCIN",
            // Small Finance Banks & Fintech
            "AUBANK", "AUSFB", "EQITAS", "UJJIVN", "JUPITE",
            "FIBANK", "SLICE", "NIYOBN",
            // Additional common sender patterns (TRAI prefixes stripped)
            "SBIUPI", "HDFCUPI", "ICIUPI", "AXISUPI",
            // Wallet & fintech
            "MOBIKWIK", "FREECHARGE", "LAZYPAY", "SIMPL", "CRED",
        )

        /**
         * Content keywords that indicate a financial transaction.
         * Used as secondary filter — SMS must contain at least one of these
         * in addition to matching a sender pattern (or if sender is unknown).
         */
        val transactionKeywords = listOf(
            // Transaction verbs
            "debited", "credited", "debit", "credit", "paid", "received",
            "sent", "transferred", "spent", "withdrawn", "deposited",
            "refund", "cashback", "reversed", "reversal",
            // Transaction channels
            "UPI", "IMPS", "NEFT", "RTGS",
            // Account patterns
            "A/c", "Acct", "account",
            // Transaction indicators
            "Txn", "transaction", "payment",
        )

        /**
         * A currency marker immediately followed by a number, e.g. "Rs.500",
         * "INR 1,200.00", "₹ 99". A bare "rs" substring is NOT enough — it
         * matches ordinary words such as "hours", "yours" or "offers".
         */
        val currencyAmountRegex = Regex(
            """(?i)(?:\brs\.?|\binr\.?|₹)\s?\d""",
        )

        /** Personal senders are plain phone numbers; bank/UPI senders are alphanumeric headers. */
        private val phoneNumberSender = Regex("""^\+?[\d\s-]{7,}$""")

        /**
         * Native pre-filter to determine if an SMS is likely a bank transaction message.
         *
         * Privacy: messages from personal phone numbers are never forwarded, and
         * every forwarded message must contain a currency amount.
         */
        fun isLikelyBankSms(address: String, body: String): Boolean {
            if (body.isBlank()) return false
            if (phoneNumberSender.matches(address.trim())) return false
            if (!currencyAmountRegex.containsMatchIn(body)) return false

            val upperAddress = address.uppercase()
            val senderMatch = bankSenderPatterns.any { pattern ->
                upperAddress.contains(pattern)
            }
            if (senderMatch) return true

            return transactionKeywords.any { keyword ->
                body.contains(keyword, ignoreCase = true)
            }
        }
    }

    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var notificationEventChannel: EventChannel
    private var applicationContext: Context? = null
    private var smsReceiver: BroadcastReceiver? = null
    private var notificationEventSink: EventChannel.EventSink? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext

        methodChannel = MethodChannel(binding.binaryMessenger, "com.pet.tracker/sms_reader")
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, "com.pet.tracker/sms_incoming")
        eventChannel.setStreamHandler(this)

        // Notification EventChannel — forwards UPI app notifications to Dart
        notificationEventChannel = EventChannel(binding.binaryMessenger, "com.pet.tracker/notification_incoming")
        notificationEventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                notificationEventSink = events
                TransactionNotificationListener.eventSink = events

                // Cached notifications are NOT pushed here: Dart drains them via
                // peekPendingNotifications + acknowledgeNotificationIds, so an
                // item is only removed after it has been stored.
            }
            override fun onCancel(arguments: Any?) {
                notificationEventSink = null
                TransactionNotificationListener.eventSink = null
            }
        })
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        notificationEventChannel.setStreamHandler(null)
        unregisterSmsReceiver()
        TransactionNotificationListener.eventSink = null
        notificationEventSink = null
        applicationContext = null
    }

    // ─── MethodChannel Handler ──────────────────────────────────────

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getInboxSms" -> {
                val lookbackMillis = call.argument<Number>("lookbackMillis")?.toLong()
                val messages = readSms("content://sms/inbox", lookbackMillis)
                result.success(messages)
            }
            "getSentSms" -> {
                // Sent-box access removed for privacy; kept for channel compatibility.
                result.success(emptyList<Map<String, Any?>>())
            }
            "getAllSms" -> {
                val lookbackMillis = call.argument<Number>("lookbackMillis")?.toLong()
                val messages = readAllSms(lookbackMillis)
                result.success(messages)
            }
            "getSmsSince" -> {
                val sinceTimestamp = call.argument<Number>("sinceTimestamp")?.toLong()
                val fallbackDays = call.argument<Number>("fallbackDays")?.toInt() ?: 7
                val messages = readSmsSince(sinceTimestamp, fallbackDays)
                result.success(messages)
            }
            "startListening" -> {
                registerSmsReceiver()
                result.success(true)
            }
            "stopListening" -> {
                unregisterSmsReceiver()
                result.success(true)
            }
            "hasNotificationAccess" -> {
                val ctx = applicationContext
                if (ctx != null) {
                    result.success(TransactionNotificationListener.hasAccess(ctx))
                } else {
                    result.success(false)
                }
            }
            "requestNotificationAccess" -> {
                val ctx = applicationContext
                if (ctx != null) {
                    TransactionNotificationListener.requestAccess(ctx)
                    result.success(true)
                } else {
                    result.success(false)
                }
            }
            "getDeviceManufacturer" -> {
                result.success(android.os.Build.MANUFACTURER ?: "unknown")
            }
            "openBatteryOptimizationSettings" -> {
                val ctx = applicationContext
                if (ctx != null) {
                    try {
                        val intent = android.content.Intent(android.provider.Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                        intent.flags = android.content.Intent.FLAG_ACTIVITY_NEW_TASK
                        ctx.startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        try {
                            val intent = android.content.Intent(
                                android.provider.Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                android.net.Uri.fromParts("package", ctx.packageName, null)
                            ).apply {
                                flags = android.content.Intent.FLAG_ACTIVITY_NEW_TASK
                            }
                            ctx.startActivity(intent)
                            result.success(true)
                        } catch (e2: Exception) {
                            result.success(false)
                        }
                    }
                } else {
                    result.success(false)
                }
            }
            "popPendingNotifications" -> {
                val ctx = applicationContext
                if (ctx != null) {
                    val list = EncryptedNotificationCache.popPendingNotifications(ctx)
                    result.success(list)
                } else {
                    result.success(emptyList<Map<String, Any?>>())
                }
            }
            "peekPendingNotifications" -> {
                val ctx = applicationContext
                if (ctx != null) {
                    val list = EncryptedNotificationCache.peekPendingNotifications(ctx)
                    result.success(list)
                } else {
                    result.success(emptyList<Map<String, Any?>>())
                }
            }
            "acknowledgeNotificationIds" -> {
                val ctx = applicationContext
                val ids = call.argument<List<String>>("ids") ?: emptyList()
                result.success(
                    if (ctx != null) EncryptedNotificationCache.acknowledgeByIds(ctx, ids) else false
                )
            }
            "clearPendingNotifications" -> {
                val ctx = applicationContext
                result.success(
                    if (ctx != null) EncryptedNotificationCache.clearAll(ctx) else false
                )
            }
            "acknowledgeNotifications" -> {
                val ctx = applicationContext
                val count = call.argument<Number>("count")?.toInt() ?: 0
                if (ctx != null) {
                    val success = EncryptedNotificationCache.acknowledgeNotifications(ctx, count)
                    result.success(success)
                } else {
                    result.success(false)
                }
            }
            else -> result.notImplemented()
        }
    }

    // ─── Read SMS from Content Provider ─────────────────────────────

    /**
     * Reads SMS messages from the specified content URI using the system ContentResolver.
     *
     * @param contentUri  "content://sms/inbox"
     * @param lookbackMillis Only return SMS newer than this many milliseconds ago.
     * @return List of maps with keys: address, body, date, type
     */
    private fun readSms(contentUri: String, lookbackMillis: Long?): List<Map<String, Any?>> {
        val context = applicationContext ?: return emptyList()
        val contentResolver: ContentResolver = context.contentResolver
        val results = mutableListOf<Map<String, Any?>>()

        val uri: Uri = Uri.parse(contentUri)
        // Include date_sent for server timestamp (more accurate than receive time)
        val projection = arrayOf("address", "body", "date", "date_sent", "type")
        val sortOrder = "date DESC"

        val selection: String?
        val selectionArgs: Array<String>?

        if (lookbackMillis != null && lookbackMillis > 0) {
            val cutoffTime = System.currentTimeMillis() - lookbackMillis
            selection = "date > ?"
            selectionArgs = arrayOf(cutoffTime.toString())
        } else {
            selection = null
            selectionArgs = null
        }

        var cursor: Cursor? = null
        try {
            cursor = contentResolver.query(uri, projection, selection, selectionArgs, sortOrder)

            if (cursor != null && cursor.moveToFirst()) {
                val addressIdx = cursor.getColumnIndexOrThrow("address")
                val bodyIdx = cursor.getColumnIndexOrThrow("body")
                val dateIdx = cursor.getColumnIndexOrThrow("date")
                val dateSentIdx = cursor.getColumnIndex("date_sent")
                val typeIdx = cursor.getColumnIndex("type")

                do {
                    val address = cursor.getString(addressIdx) ?: ""
                    val body = cursor.getString(bodyIdx) ?: ""
                    val date = cursor.getLong(dateIdx)
                    val dateSent = if (dateSentIdx >= 0) cursor.getLong(dateSentIdx) else 0L
                    val type = if (typeIdx >= 0) cursor.getInt(typeIdx) else 1

                    // Native-side pre-filter: only pass likely bank/UPI SMS
                    if (isLikelyBankSms(address, body)) {
                        results.add(
                            mapOf(
                                "address" to address,
                                "body" to body,
                                "date" to date,
                                "date_sent" to dateSent,
                                "type" to type  // 1=inbox, 2=sent, 3=draft, etc.
                            )
                        )
                    }
                } while (cursor.moveToNext())
            }
        } catch (e: SecurityException) {
            SafeLog.w("SmsReaderPlugin", "SMS permission denied: ${e.message}")
        } catch (e: Exception) {
            SafeLog.e("SmsReaderPlugin", "Error reading SMS from $contentUri: ${e.message}", e)
        } finally {
            cursor?.close()
        }

        SafeLog.d("SmsReaderPlugin", "readSms($contentUri): found ${results.size} bank SMS")
        return results
    }

    /**
     * Reads received SMS only (inbox). Kept under the legacy "getAllSms" name.
     * This is useful for comprehensive scanning on first install.
     */
    private fun readAllSms(lookbackMillis: Long?): List<Map<String, Any?>> {
        return readSms("content://sms/inbox", lookbackMillis)
    }

    /**
     * Reads SMS since an absolute timestamp (milliseconds since epoch).
     * Used by the reconciliation sweep for incremental processing.
     *
     * Falls back to [fallbackDays]-day lookback if [sinceTimestamp] is null,
     * zero, negative, or in the future (corrupted watermark).
     *
     * @param sinceTimestamp  Absolute epoch-millis cutoff. Nullable for safety.
     * @param fallbackDays   Days to look back when timestamp is unusable.
     * @return List of maps with keys: address, body, date, date_sent, type
     */
    private fun readSmsSince(sinceTimestamp: Long?, fallbackDays: Int): List<Map<String, Any?>> {
        val context = applicationContext ?: return emptyList()
        val contentResolver: ContentResolver = context.contentResolver
        val results = mutableListOf<Map<String, Any?>>()

        val now = System.currentTimeMillis()

        // Validate the watermark timestamp. If it's missing, zero, negative,
        // or in the future, fall back to a relative lookback.
        val cutoffTime: Long = if (sinceTimestamp != null && sinceTimestamp > 0 && sinceTimestamp < now) {
            sinceTimestamp
        } else {
            now - (fallbackDays.toLong().coerceIn(1, 365) * 24 * 60 * 60 * 1000L)
        }

        val uri: Uri = Uri.parse("content://sms/inbox")
        // Include date_sent for server timestamp (more accurate than receive time)
        val projection = arrayOf("address", "body", "date", "date_sent", "type")
        val selection = "date > ?"
        val selectionArgs = arrayOf(cutoffTime.toString())
        val sortOrder = "date ASC" // oldest first for sequential watermark advancement

        var cursor: Cursor? = null
        try {
            cursor = contentResolver.query(uri, projection, selection, selectionArgs, sortOrder)

            if (cursor != null && cursor.moveToFirst()) {
                val addressIdx = cursor.getColumnIndexOrThrow("address")
                val bodyIdx = cursor.getColumnIndexOrThrow("body")
                val dateIdx = cursor.getColumnIndexOrThrow("date")
                val dateSentIdx = cursor.getColumnIndex("date_sent")
                val typeIdx = cursor.getColumnIndex("type")

                do {
                    val address = cursor.getString(addressIdx) ?: ""
                    val body = cursor.getString(bodyIdx) ?: ""
                    val date = cursor.getLong(dateIdx)
                    val dateSent = if (dateSentIdx >= 0) cursor.getLong(dateSentIdx) else 0L
                    val type = if (typeIdx >= 0) cursor.getInt(typeIdx) else 1

                    if (isLikelyBankSms(address, body)) {
                        results.add(
                            mapOf(
                                "address" to address,
                                "body" to body,
                                "date" to date,
                                "date_sent" to dateSent,
                                "type" to type
                            )
                        )
                    }
                } while (cursor.moveToNext())
            }
        } catch (e: SecurityException) {
            SafeLog.w("SmsReaderPlugin", "SMS permission denied for reconciliation: ${e.message}")
        } catch (e: Exception) {
            SafeLog.e("SmsReaderPlugin", "Error reading SMS since $cutoffTime: ${e.message}", e)
        } finally {
            cursor?.close()
        }

        SafeLog.d("SmsReaderPlugin", "readSmsSince: cutoff=${cutoffTime}, found=${results.size} bank SMS")
        return results
    }


    // ─── Live SMS Listener ──────────────────────────────────────────

    /**
     * Live SMS delivery is handled solely by the manifest-declared
     * [SmsBroadcastReceiver], which forwards to [eventSink]. A second,
     * dynamically registered receiver used to deliver every SMS twice and
     * caused duplicate transactions, so these are intentionally no-ops
     * (kept for MethodChannel compatibility).
     */
    private fun registerSmsReceiver() {}

    private fun unregisterSmsReceiver() {
        smsReceiver = null
    }

    // ─── EventChannel StreamHandler ─────────────────────────────────

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        registerSmsReceiver()
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        unregisterSmsReceiver()
    }
}
