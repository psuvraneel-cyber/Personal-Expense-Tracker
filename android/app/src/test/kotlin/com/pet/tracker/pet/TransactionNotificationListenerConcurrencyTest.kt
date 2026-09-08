package com.pet.tracker.pet

import android.app.Notification
import android.content.Context
import android.os.Bundle
import android.service.notification.StatusBarNotification
import androidx.test.core.app.ApplicationProvider
import io.flutter.plugin.common.EventChannel
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.kotlin.any
import org.mockito.kotlin.doAnswer
import org.mockito.kotlin.mock
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.LooperMode
import org.robolectric.shadows.ShadowLooper
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

@RunWith(RobolectricTestRunner::class)
@LooperMode(LooperMode.Mode.PAUSED)
class TransactionNotificationListenerConcurrencyTest {

    private lateinit var context: Context
    private lateinit var listener: TransactionNotificationListener

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        TransactionNotificationListener.resetForTesting()
        EncryptedNotificationCache.resetForTesting()

        TransactionNotificationListener.listenerContext = context

        // Mock encrypted storage to store items in memory for verification
        val fakeEncryptedPrefs = context.getSharedPreferences("test_listener_concurrency", Context.MODE_PRIVATE)
        EncryptedNotificationCache.encryptedPrefsFactory = { fakeEncryptedPrefs }

        listener = TransactionNotificationListener()
    }

    @After
    fun tearDown() {
        TransactionNotificationListener.resetForTesting()
        EncryptedNotificationCache.resetForTesting()
    }

    private fun createMockNotification(pkg: String, bodyText: String): StatusBarNotification {
        val sbn = mock<StatusBarNotification>()
        org.mockito.kotlin.whenever(sbn.packageName).thenReturn(pkg)

        val notification = Notification()
        val extras = Bundle()
        extras.putCharSequence("android.title", "Bank Alert")
        extras.putCharSequence("android.text", bodyText)
        notification.extras = extras

        org.mockito.kotlin.whenever(sbn.notification).thenReturn(notification)

        return sbn
    }

    /**
     * 1. Test check-then-act race elimination during cancellation.
     * When eventSink is set to null (onCancel) while a notification Runnable is in the Main Looper queue,
     * the notification MUST NOT call success() on the cancelled sink, but instead save to cache.
     */
    @Test
    fun testCheckThenActRaceElimination_onCancelPriorToExecution() {
        val deliveredCount = AtomicInteger(0)
        val isSinkCancelled = AtomicBoolean(false)

        val mockSink = mock<EventChannel.EventSink> {
            on { success(any()) } doAnswer {
                if (isSinkCancelled.get()) {
                    throw IllegalStateException("EventSink called after cancellation!")
                }
                deliveredCount.incrementAndGet()
                Unit
            }
        }

        // Attach sink
        TransactionNotificationListener.eventSink = mockSink

        // Post notification (background Binder thread simulated)
        val sbn = createMockNotification("com.phonepe.app", "Paid Rs 450 to Swiggy")
        listener.onNotificationPosted(sbn)

        // Cancel sink BEFORE Main Looper flushes
        isSinkCancelled.set(true)
        TransactionNotificationListener.eventSink = null

        // Execute queued Runnable on Main Looper
        ShadowLooper.runUiThreadTasksIncludingDelayedTasks()

        // Assert: success() was NOT called on the cancelled sink (0 delivered to cancelled sink)
        assertEquals(0, deliveredCount.get())

        // Assert: Notification was safely preserved in EncryptedNotificationCache
        val popped = EncryptedNotificationCache.popPendingNotifications(context)
        assertEquals(1, popped.size)
        assertEquals("com.phonepe.app", popped[0]["package"])
    }

    /**
     * 2. Test rapid reconnect / sink replacement race.
     * When eventSink is replaced with newSink before Main Looper flushes,
     * the event is delivered to the newSink (not lost, not delivered to oldSink).
     */
    @Test
    fun testSinkReplacement_DeliversToNewActiveSink() {
        val oldSinkDelivered = AtomicInteger(0)
        val newSinkDelivered = AtomicInteger(0)

        val oldSink = mock<EventChannel.EventSink> {
            on { success(any()) } doAnswer {
                oldSinkDelivered.incrementAndGet()
                Unit
            }
        }

        val newSink = mock<EventChannel.EventSink> {
            on { success(any()) } doAnswer {
                newSinkDelivered.incrementAndGet()
                Unit
            }
        }

        // Attach old sink
        TransactionNotificationListener.eventSink = oldSink

        // Post notification
        val sbn = createMockNotification("com.google.android.apps.nbu.paisa.user", "Rs 120 debited")
        listener.onNotificationPosted(sbn)

        // Reconnect: replaces oldSink with newSink BEFORE Main Looper flushes
        TransactionNotificationListener.eventSink = newSink

        // Execute queued Runnable on Main Looper
        ShadowLooper.runUiThreadTasksIncludingDelayedTasks()

        // Assert: Event was delivered to newSink, NOT oldSink
        assertEquals(0, oldSinkDelivered.get())
        assertEquals(1, newSinkDelivered.get())
    }

    /**
     * 3. Mass Concurrency Stress Test: Thousands of concurrent onNotificationPosted,
     * onListen, onCancel, reconnects across background threads.
     */
    @Test
    fun testMassiveConcurrentListenerRecreationAndPostings() {
        val threadCount = 8
        val postingsPerThread = 100
        val executor = Executors.newFixedThreadPool(threadCount)
        val latch = CountDownLatch(threadCount)

        val totalDeliveredToActiveSink = AtomicInteger(0)
        val illegalStateExceptionsEncountered = AtomicInteger(0)

        val activeSinks = ConcurrentLinkedQueue<EventChannel.EventSink>()

        // Helper to create valid active mock sink
        fun createSink(): EventChannel.EventSink {
            val sink = mock<EventChannel.EventSink> {
                on { success(any()) } doAnswer {
                    totalDeliveredToActiveSink.incrementAndGet()
                    Unit
                }
            }
            activeSinks.add(sink)
            return sink
        }

        // Thread 0: Simulates rapid onListen / onCancel churn on main thread
        val churnActive = AtomicBoolean(true)
        val churnExecutor = Executors.newSingleThreadExecutor()
        churnExecutor.submit {
            while (churnActive.get()) {
                val newSink = createSink()
                TransactionNotificationListener.eventSink = newSink
                Thread.sleep(5)
                TransactionNotificationListener.eventSink = null
                Thread.sleep(5)
            }
        }

        // Worker threads: Concurrent onNotificationPosted calls
        for (t in 0 until threadCount) {
            executor.submit {
                try {
                    for (i in 0 until postingsPerThread) {
                        val sbn = createMockNotification("net.one97.paytm", "INR ${i + 1} paid to Merchant_$i")
                        try {
                            listener.onNotificationPosted(sbn)
                        } catch (e: IllegalStateException) {
                            illegalStateExceptionsEncountered.incrementAndGet()
                        }
                    }
                } finally {
                    latch.countDown()
                }
            }
        }

        val completed = latch.await(15, TimeUnit.SECONDS)
        assertTrue("Concurrent posting tasks completed", completed)

        churnActive.set(false)
        churnExecutor.shutdown()
        executor.shutdown()

        // Flush all main looper tasks posted by background threads
        ShadowLooper.runUiThreadTasksIncludingDelayedTasks()

        // Zero IllegalStateExceptions MUST occur under concurrency
        assertEquals(0, illegalStateExceptionsEncountered.get())

        // Verify Total Conservation Invariant: Every notification posted is either
        // delivered to an active sink OR cached in EncryptedNotificationCache.
        val totalPosted = threadCount * postingsPerThread // 800 notifications
        val cachedCount = EncryptedNotificationCache.popPendingNotifications(context).size
        val deliveredCount = totalDeliveredToActiveSink.get()

        assertEquals(
            "Every notification must be accounted for (Delivered: $deliveredCount, Cached: $cachedCount)",
            totalPosted,
            deliveredCount + cachedCount
        )
    }
}
