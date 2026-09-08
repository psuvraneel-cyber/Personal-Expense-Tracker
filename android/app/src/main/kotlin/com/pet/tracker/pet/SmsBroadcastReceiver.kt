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
 *      - Persists to [EncryptedNotificationCache] using AES-256 GCM encrypted storage.
 *      - Delivers to [SmsReaderPlugin.eventSink] if foreground session is active.
 *      - Enqueues an expedited OneTimeWorkRequest via WorkManager to trigger [smsCallbackDispatcher]
 *        in a background Dart isolate within seconds.
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
                timestampByAddress[address] = smsMessage.timestampMillis
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

                // 1. Persist to encrypted cache for safe non-volatile persistence
                try {
                    EncryptedNotificationCache.saveNotification(context, messageData)
                } catch (e: Exception) {
                    SafeLog.e(TAG, "Failed to cache incoming SMS: ${e.message}", e)
                }

                // 2. Deliver to live Flutter eventSink if active
                val sink = SmsReaderPlugin.eventSink
                if (sink != null) {
                    Handler(Looper.getMainLooper()).post {
                        try {
                            sink.success(messageData)
                        } catch (e: Exception) {
                            SafeLog.e(TAG, "Failed to deliver SMS to live EventSink: ${e.message}")
                        }
                    }
                }
            }
        }

        // 3. If any bank SMS was captured, enqueue expedited WorkManager one-off task
        if (bankSmsCount > 0) {
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
                ExistingWorkPolicy.REPLACE,
                workRequest
            )
            SafeLog.d(TAG, "Enqueued expedited WorkManager task ($WORK_NAME_EXPEDITED_SCAN)")
        } catch (e: Exception) {
            SafeLog.e(TAG, "Failed to enqueue expedited WorkManager scan: ${e.message}", e)
        }
    }
}
