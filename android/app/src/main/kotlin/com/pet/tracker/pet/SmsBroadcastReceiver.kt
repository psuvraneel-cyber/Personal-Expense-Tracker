package com.pet.tracker.pet

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Telephony
import android.telephony.SmsMessage
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequest
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import dev.fluttercommunity.workmanager.BackgroundWorker

/**
 * Static BroadcastReceiver for android.provider.Telephony.SMS_RECEIVED.
 *
 * ## Architecture & Reliability:
 * - Declared statically in AndroidManifest.xml to ensure real-time transaction capture
 *   even when the application process is completely stopped/killed by the OS or swiped away.
 * - SMS_RECEIVED is a protected system broadcast that is explicitly exempt from
 *   Android 8+ (API 26) through Android 15 (API 35) background manifest receiver restrictions
 *   for apps with granted RECEIVE_SMS permission.
 * - Protected with `android:permission="android.permission.BROADCAST_SMS"` so only the
 *   Android OS Telephony framework can invoke this receiver.
 * - On receive:
 *   1. Reconstructs multi-part SMS PDU fragments per sender address.
 *   2. Pre-filters with [SmsReaderPlugin.isLikelyBankSms].
 *   3. If valid bank SMS:
 *      - Delivers to [SmsReaderPlugin.eventSink] if the app is running (the only
 *        live delivery path — the plugin no longer registers a second receiver).
 *      - Otherwise enqueues an expedited WorkManager inbox scan in a background
 *        Dart isolate. The system SMS provider is the durable store.
 */
class SmsBroadcastReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "SmsBroadcastReceiver"
        const val TASK_SMS_SCAN = "com.pet.tracker.smsInboxScan"
        const val WORK_NAME_EXPEDITED_SCAN = "com.pet.tracker.smsInboxScan.immediate"
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent == null) return
        if (intent.action != Telephony.Sms.Intents.SMS_RECEIVED_ACTION) return

        val bundle = intent.extras ?: return
        val pdus = bundle.get("pdus") as? Array<*> ?: return
        val format = bundle.getString("format") ?: ""

        // Group PDU fragments by originating address to handle multi-part SMS correctly.
        val messagesByAddress = mutableMapOf<String, StringBuilder>()
        val timestampByAddress = mutableMapOf<String, Long>()

        for (pdu in pdus) {
            if (pdu !is ByteArray) continue

            val smsMessage: SmsMessage = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                SmsMessage.createFromPdu(pdu, format)
            } else {
                @Suppress("DEPRECATION")
                SmsMessage.createFromPdu(pdu)
            }

            val address = smsMessage.displayOriginatingAddress ?: ""
            val bodyPart = smsMessage.displayMessageBody ?: ""

            messagesByAddress.getOrPut(address) { StringBuilder() }.append(bodyPart)
            if (!timestampByAddress.containsKey(address)) {
                // Use the device receive time — the same clock the SMS provider
                // stores in its `date` column, which inbox scans read. The
                // SMSC `timestampMillis` can differ by hours on some networks,
                // which would defeat cross-path deduplication.
                timestampByAddress[address] = System.currentTimeMillis()
            }
        }

        var bankSmsCount = 0

        for ((address, bodyBuilder) in messagesByAddress) {
            val body = bodyBuilder.toString()
            if (body.isBlank()) continue

            if (SmsReaderPlugin.isLikelyBankSms(address, body)) {
                bankSmsCount++
                val timestamp = timestampByAddress[address] ?: System.currentTimeMillis()
                val messageData = mapOf(
                    "address" to address,
                    "body" to body,
                    "date" to timestamp,
                    "type" to 1,
                    "source" to "sms"
                )

                SafeLog.d(TAG, "Static SMS_RECEIVED captured bank SMS from $address")

                // Single delivery path: live to Flutter when the app is running.
                // The message is already persisted by the system SMS provider,
                // so no extra cache copy is needed — if the app isn't running
                // (or live delivery fails) the inbox scan below picks it up.
                val sink = SmsReaderPlugin.eventSink
                if (sink != null) {
                    Handler(Looper.getMainLooper()).post {
                        try {
                            sink.success(messageData)
                        } catch (e: Exception) {
                            SafeLog.e(TAG, "Failed to deliver SMS to live EventSink: ${e.message}")
                            enqueueExpeditedSmsScan(context)
                        }
                    }
                }
            }
        }

        // App not running: process via an expedited background inbox scan.
        if (bankSmsCount > 0 && SmsReaderPlugin.eventSink == null) {
            enqueueExpeditedSmsScan(context)
        }
    }

    private fun enqueueExpeditedSmsScan(context: Context) {
        try {
            val inputData = Data.Builder()
                .putString(BackgroundWorker.DART_TASK_KEY, TASK_SMS_SCAN)
                .build()

            val workRequestBuilder = OneTimeWorkRequest.Builder(BackgroundWorker::class.java)
                .setInputData(inputData)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                workRequestBuilder.setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
            }

            val workRequest = workRequestBuilder.build()

            WorkManager.getInstance(context).enqueueUniqueWork(
                WORK_NAME_EXPEDITED_SCAN,
                ExistingWorkPolicy.APPEND_OR_REPLACE, // never cancel an in-flight import
                workRequest
            )
            SafeLog.d(TAG, "Enqueued expedited WorkManager task ($WORK_NAME_EXPEDITED_SCAN)")
        } catch (e: Exception) {
            SafeLog.e(TAG, "Failed to enqueue expedited WorkManager scan: ${e.message}", e)
        }
    }
}
