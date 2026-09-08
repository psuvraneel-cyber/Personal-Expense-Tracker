package com.pet.tracker.pet

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.security.KeyStoreException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

@RunWith(RobolectricTestRunner::class)
class EncryptedNotificationCacheTest {

    private lateinit var context: Context

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        EncryptedNotificationCache.resetForTesting()
    }

    @After
    fun tearDown() {
        EncryptedNotificationCache.resetForTesting()
    }

    /**
     * 1. Test normal encrypted operation.
     * Notifications are saved and retrieved via encrypted SharedPreferences.
     */
    @Test
    fun testNormalEncryptedOperation() {
        val fakeEncryptedPrefs = context.getSharedPreferences("test_encrypted_prefs", Context.MODE_PRIVATE)
        EncryptedNotificationCache.encryptedPrefsFactory = { fakeEncryptedPrefs }

        val notif1 = mapOf("id" to "1", "title" to "HDFC", "amount" to 500.0)
        val notif2 = mapOf("id" to "2", "title" to "ICICI", "amount" to 1200.0)

        EncryptedNotificationCache.saveNotification(context, notif1)
        EncryptedNotificationCache.saveNotification(context, notif2)

        // Ensure RAM queue remains empty since encrypted prefs is operational
        assertEquals(0, EncryptedNotificationCache.getInMemoryQueueSizeForTesting())

        val popped = EncryptedNotificationCache.popPendingNotifications(context)
        assertEquals(2, popped.size)
        assertEquals("1", popped[0]["id"])
        assertEquals("2", popped[1]["id"])

        // After pop, store is cleared
        val poppedAgain = EncryptedNotificationCache.popPendingNotifications(context)
        assertTrue(poppedAgain.isEmpty())
    }

    /**
     * 2. Test Keystore initialization failure.
     * When encrypted prefs factory throws (simulating Keystore corruption),
     * notifications must go ONLY to RAM queue. Plaintext disk fallback MUST NOT be created.
     */
    @Test
    fun testKeystoreInitializationFailure_NoPlaintextDiskFallback() {
        // Force encrypted prefs creation to fail completely
        EncryptedNotificationCache.encryptedPrefsFactory = {
            throw KeyStoreException("AndroidKeyStore unavailable: Keystore corrupt")
        }

        val notif1 = mapOf("id" to "100", "title" to "SBI", "amount" to 2500.0)

        // Act
        EncryptedNotificationCache.saveNotification(context, notif1)

        // Assert: Notification buffered in memory
        assertEquals(1, EncryptedNotificationCache.getInMemoryQueueSizeForTesting())

        // Verify: No plaintext fallback file "pet_notification_cache_v2_fallback" exists on disk
        val fallbackPrefs = context.getSharedPreferences("pet_notification_cache_v2_fallback", Context.MODE_PRIVATE)
        assertFalse(fallbackPrefs.contains("pending_notifications"))

        // Verify: Pop still works from RAM while Keystore is down
        val popped = EncryptedNotificationCache.popPendingNotifications(context)
        assertEquals(1, popped.size)
        assertEquals("100", popped[0]["id"])
        assertEquals(0, EncryptedNotificationCache.getInMemoryQueueSizeForTesting())
    }

    /**
     * 3. Test recovery after Keystore restoration.
     * When Keystore fails initially, notifications accumulate in RAM.
     * When Keystore recovers, getPrefs() / saveNotification() flushes RAM queue to encrypted store.
     */
    @Test
    fun testRecoveryAfterKeystoreRestoration() {
        // Step 1: Keystore is broken initially
        EncryptedNotificationCache.encryptedPrefsFactory = {
            throw KeyStoreException("Keystore temporarily uninitialized")
        }

        val notif1 = mapOf("id" to "N1", "body" to "First in RAM")
        val notif2 = mapOf("id" to "N2", "body" to "Second in RAM")

        EncryptedNotificationCache.saveNotification(context, notif1)
        EncryptedNotificationCache.saveNotification(context, notif2)

        assertEquals(2, EncryptedNotificationCache.getInMemoryQueueSizeForTesting())

        // Step 2: Keystore recovers!
        val fakeEncryptedPrefs = context.getSharedPreferences("test_recovered_prefs", Context.MODE_PRIVATE)
        EncryptedNotificationCache.encryptedPrefsFactory = { fakeEncryptedPrefs }

        val notif3 = mapOf("id" to "N3", "body" to "Third in Encrypted")
        EncryptedNotificationCache.saveNotification(context, notif3)

        // Assert: RAM queue was flushed into encrypted storage
        assertEquals(0, EncryptedNotificationCache.getInMemoryQueueSizeForTesting())

        // Step 3: Pop all notifications and verify exact FIFO ordering (N1 -> N2 -> N3)
        val popped = EncryptedNotificationCache.popPendingNotifications(context)
        assertEquals(3, popped.size)
        assertEquals("N1", popped[0]["id"])
        assertEquals("N2", popped[1]["id"])
        assertEquals("N3", popped[2]["id"])
    }

    /**
     * 4. Test process death during fallback mode.
     * If Keystore is broken and process dies, RAM queue is cleared and NO plaintext data persists.
     */
    @Test
    fun testProcessDeathDuringFallbackMode() {
        // Keystore is broken
        EncryptedNotificationCache.encryptedPrefsFactory = {
            throw KeyStoreException("Permanent hardware key error")
        }

        val notif = mapOf("id" to "RAM_ONLY", "amount" to 999.0)
        EncryptedNotificationCache.saveNotification(context, notif)
        assertEquals(1, EncryptedNotificationCache.getInMemoryQueueSizeForTesting())

        // Simulate Process Death: clear in-memory state
        EncryptedNotificationCache.resetForTesting()

        // Verify: Memory queue is empty
        assertEquals(0, EncryptedNotificationCache.getInMemoryQueueSizeForTesting())

        // Verify: Disk has ZERO plaintext fallback data
        val fallbackPrefs = context.getSharedPreferences("pet_notification_cache_v2_fallback", Context.MODE_PRIVATE)
        assertTrue(fallbackPrefs.all.isEmpty())

        // Popping notifications yields empty list
        val popped = EncryptedNotificationCache.popPendingNotifications(context)
        assertTrue(popped.isEmpty())
    }

    /**
     * 5. Test ordering preservation across multiple state shifts.
     */
    @Test
    fun testOrderingPreservation() {
        val fakeEncryptedPrefs = context.getSharedPreferences("test_ordering_prefs", Context.MODE_PRIVATE)

        // Phase 1: Operational -> Save 1 & 2
        EncryptedNotificationCache.encryptedPrefsFactory = { fakeEncryptedPrefs }
        EncryptedNotificationCache.saveNotification(context, mapOf("idx" to 1))
        EncryptedNotificationCache.saveNotification(context, mapOf("idx" to 2))

        // Phase 2: Keystore Fails -> Save 3 & 4 (buffered in RAM)
        EncryptedNotificationCache.encryptedPrefsFactory = { throw KeyStoreException("Temporary failure") }
        EncryptedNotificationCache.saveNotification(context, mapOf("idx" to 3))
        EncryptedNotificationCache.saveNotification(context, mapOf("idx" to 4))

        // Phase 3: Keystore Recovers -> Save 5
        EncryptedNotificationCache.encryptedPrefsFactory = { fakeEncryptedPrefs }
        EncryptedNotificationCache.saveNotification(context, mapOf("idx" to 5))

        // Act: Pop all
        val popped = EncryptedNotificationCache.popPendingNotifications(context)

        // Assert: Strict 1, 2, 3, 4, 5 FIFO sequence
        assertEquals(5, popped.size)
        for (i in 0 until 5) {
            assertEquals(i + 1, (popped[i]["idx"] as Number).toInt())
        }
    }

    /**
     * 6. Test bounded queue capacity limit and oldest-item eviction.
     */
    @Test
    fun testBoundedQueueCapacityEviction() {
        // Keystore is broken
        EncryptedNotificationCache.encryptedPrefsFactory = {
            throw KeyStoreException("Keystore broken")
        }

        val capacity = EncryptedNotificationCache.MAX_IN_MEMORY_CAPACITY // 200

        // Push 250 items (exceeding capacity by 50)
        for (i in 1..250) {
            EncryptedNotificationCache.saveNotification(context, mapOf("id" to i))
        }

        // Assert: Queue size capped at MAX_IN_MEMORY_CAPACITY (200)
        assertEquals(capacity, EncryptedNotificationCache.getInMemoryQueueSizeForTesting())

        // Pop all items from RAM
        val popped = EncryptedNotificationCache.popPendingNotifications(context)
        assertEquals(capacity, popped.size)

        // Assert: Oldest 50 items (1..50) were evicted; first remaining item is 51
        assertEquals(51, (popped[0]["id"] as Number).toInt())
        assertEquals(250, (popped[199]["id"] as Number).toInt())
    }

    /**
     * 7. Test atomic non-destructive flush safety when disk write fails.
     * If disk write throws an exception during flush, items MUST remain intact in RAM queue.
     */
    @Test
    fun testAtomicFlushPreservesQueueOnDiskFailure() {
        // Phase 1: Keystore broken, 3 items buffer in RAM
        EncryptedNotificationCache.encryptedPrefsFactory = { throw KeyStoreException("Initial failure") }
        EncryptedNotificationCache.saveNotification(context, mapOf("id" to "A"))
        EncryptedNotificationCache.saveNotification(context, mapOf("id" to "B"))
        EncryptedNotificationCache.saveNotification(context, mapOf("id" to "C"))
        assertEquals(3, EncryptedNotificationCache.getInMemoryQueueSizeForTesting())

        // Phase 2: Keystore returns instance, but disk edit throws RuntimeException during flush
        val brokenDiskPrefs = org.mockito.kotlin.mock<android.content.SharedPreferences> {
            on { getString(org.mockito.kotlin.any(), org.mockito.kotlin.any()) }.thenReturn("[]")
            on { edit() }.thenThrow(RuntimeException("Disk I/O error during commit"))
        }

        EncryptedNotificationCache.encryptedPrefsFactory = { brokenDiskPrefs }

        // Attempting to save notification calls getPrefs() -> flushInMemoryQueueLocked()
        EncryptedNotificationCache.saveNotification(context, mapOf("id" to "D"))

        // Assert: Flush failed safely! All items (A, B, C) remain intact in RAM + D added
        assertTrue(EncryptedNotificationCache.getInMemoryQueueSizeForTesting() >= 3)

        // Phase 3: Disk recovers cleanly
        val recoveredPrefs = context.getSharedPreferences("test_atomic_recovery_prefs", Context.MODE_PRIVATE)
        EncryptedNotificationCache.encryptedPrefsFactory = { recoveredPrefs }

        val popped = EncryptedNotificationCache.popPendingNotifications(context)
        assertTrue(popped.size >= 4)
        assertEquals("A", popped[0]["id"])
        assertEquals("B", popped[1]["id"])
        assertEquals("C", popped[2]["id"])
    }

    /**
     * 8. Test multi-threaded concurrent save & pop operations.
     */
    @Test
    fun testMultiThreadedConcurrentAccess() {
        val fakeEncryptedPrefs = context.getSharedPreferences("test_concurrent_prefs", Context.MODE_PRIVATE)
        EncryptedNotificationCache.encryptedPrefsFactory = { fakeEncryptedPrefs }

        val threadCount = 10
        val itemsPerThread = 50
        val executor = Executors.newFixedThreadPool(threadCount)
        val latch = CountDownLatch(threadCount)

        for (t in 0 until threadCount) {
            val threadId = t
            executor.submit {
                try {
                    for (i in 0 until itemsPerThread) {
                        val data = mapOf("thread" to threadId, "item" to i)
                        EncryptedNotificationCache.saveNotification(context, data)
                    }
                } finally {
                    latch.countDown()
                }
            }
        }

        val completed = latch.await(10, TimeUnit.SECONDS)
        assertTrue("Concurrent tasks finished in time", completed)
        executor.shutdown()

        val popped = EncryptedNotificationCache.popPendingNotifications(context)
        assertEquals(threadCount * itemsPerThread, popped.size)
    }

    /**
     * 9. Test migration of legacy fallback file from older app versions.
     */
    @Test
    fun testLegacyFallbackFileMigrationAndDeletion() {
        // Pre-populate old legacy fallback file "pet_notification_cache_v2_fallback"
        val fallbackPrefs = context.getSharedPreferences("pet_notification_cache_v2_fallback", Context.MODE_PRIVATE)
        fallbackPrefs.edit().putString("pending_notifications", """[{"id":"LEGACY_1"}]""").commit()

        val fakeEncryptedPrefs = context.getSharedPreferences("test_migration_target", Context.MODE_PRIVATE)
        EncryptedNotificationCache.encryptedPrefsFactory = { fakeEncryptedPrefs }

        // Trigger migration by calling getPrefs()
        EncryptedNotificationCache.getPrefs(context)

        // Assert: Legacy data moved to encrypted store
        val popped = EncryptedNotificationCache.popPendingNotifications(context)
        assertEquals(1, popped.size)
        assertEquals("LEGACY_1", popped[0]["id"])

        // Assert: Legacy fallback pref was cleared
        assertFalse(fallbackPrefs.contains("pending_notifications"))
    }
}
