package com.pet.tracker.pet

import android.content.Context
import android.content.Intent
import android.provider.Telephony
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class SmsBroadcastReceiverTest {

    private lateinit var context: Context
    private lateinit var receiver: SmsBroadcastReceiver

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        receiver = SmsBroadcastReceiver()
        EncryptedNotificationCache.resetForTesting()
    }

    @After
    fun tearDown() {
        EncryptedNotificationCache.resetForTesting()
    }

    @Test
    fun testIsLikelyBankSms_RecognizesBankSenders() {
        assertTrue(SmsReaderPlugin.isLikelyBankSms("AD-HDFCBK", "Your account has been debited"))
        assertTrue(SmsReaderPlugin.isLikelyBankSms("VM-ICICIB", "Rs 500 paid at Starbucks"))
        assertTrue(SmsReaderPlugin.isLikelyBankSms("SBIINB", "INR 1,200.00 debited"))
        assertTrue(SmsReaderPlugin.isLikelyBankSms("AXISBK", "₹2,500 transferred to John"))
        assertTrue(SmsReaderPlugin.isLikelyBankSms("PAYTM", "Payment of Rs 150 successful"))
        assertTrue(SmsReaderPlugin.isLikelyBankSms("GPAY", "You sent INR 300 via UPI"))
    }

    @Test
    fun testIsLikelyBankSms_RecognizesFinancialKeywordsWithCurrency() {
        // Unknown sender but contains transaction keywords and currency indicator
        assertTrue(SmsReaderPlugin.isLikelyBankSms("+919876543210", "Rs 500 spent at Grocery Store on card ending 1234"))
        assertTrue(SmsReaderPlugin.isLikelyBankSms("123456", "INR 1000 deposited to your account successfully"))
        assertTrue(SmsReaderPlugin.isLikelyBankSms("INFO", "₹450 debited for UPI ref 998877"))
    }

    @Test
    fun testIsLikelyBankSms_RejectsNonBankAndSpamMessages() {
        // Personal message
        assertFalse(SmsReaderPlugin.isLikelyBankSms("+919876543210", "Hey, are we still meeting today for coffee?"))
        // OTP from non-financial auth service without financial transaction details
        assertFalse(SmsReaderPlugin.isLikelyBankSms("TX-AUTHMSG", "Your verification code is 123456"))
        // Currency without transaction keywords
        assertFalse(SmsReaderPlugin.isLikelyBankSms("+919876543210", "I will return 500 tomorrow maybe"))
        // Empty message
        assertFalse(SmsReaderPlugin.isLikelyBankSms("AD-HDFCBK", ""))
        assertFalse(SmsReaderPlugin.isLikelyBankSms("AD-HDFCBK", "   "))
    }

    @Test
    fun testOnReceive_IgnoresIrrelevantIntentsGracefully() {
        val nonSmsIntent = Intent(Intent.ACTION_BOOT_COMPLETED)
        receiver.onReceive(context, nonSmsIntent)

        // No notifications should be saved to cache
        val pending = EncryptedNotificationCache.popPendingNotifications(context)
        assertTrue(pending.isEmpty())
    }

    @Test
    fun testOnReceive_HandlesNullParametersSafely() {
        // Should not throw NPE
        receiver.onReceive(null, null)
        receiver.onReceive(context, null)
        receiver.onReceive(null, Intent(Telephony.Sms.Intents.SMS_RECEIVED_ACTION))
    }

    @Test
    fun testTaskConstants() {
        assertEquals("com.pet.tracker.smsInboxScan", SmsBroadcastReceiver.TASK_SMS_SCAN)
        assertEquals("com.pet.tracker.smsInboxScan.immediate", SmsBroadcastReceiver.WORK_NAME_EXPEDITED_SCAN)
    }
}
