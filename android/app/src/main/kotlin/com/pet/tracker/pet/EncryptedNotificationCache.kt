package com.pet.tracker.pet

import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import androidx.annotation.VisibleForTesting
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import org.json.JSONArray
import org.json.JSONObject
import java.util.Queue
import java.util.concurrent.ConcurrentLinkedQueue

/**
 * Production-grade encrypted storage for pending transaction notifications.
 *
 * ## Security & Privacy Architecture:
 * - Uses Jetpack Security Crypto (`EncryptedSharedPreferences` + `MasterKey` AES256_GCM).
 * - Stores pending notification payloads strictly in encrypted storage at `pet_notification_cache_v2`.
 * - Migrates legacy plaintext `pet_notification_cache` and legacy fallback files on first launch,
 *   wiping plaintext files from disk.
 *
 * ## Zero-Plaintext Policy:
 * Financial notification payloads contain sensitive PII (transaction amounts, merchant names, title, body).
 * Under no circumstances may notification data ever be stored in unencrypted plaintext `SharedPreferences`
 * or written to disk without AES-256 encryption.
 *
 * ## Fail-Safe In-Memory Fallback & Recovery Strategy:
 * 1. **Keystore Outage Handling:** If `EncryptedSharedPreferences` fails to initialize (e.g., due to
 *    Android Keystore corruption, hardware key store errors, or OS update glitches), the system
 *    NEVER falls back to plaintext disk storage.
 * 2. **Process-Bound Bounded In-Memory Queue:** Notifications are buffered strictly in RAM using
 *    a bounded in-memory FIFO queue (`inMemoryQueue`, max capacity = 200). If capacity is reached,
 *    the oldest item is evicted to guarantee zero risk of OutOfMemoryError (OOM) crashes.
 * 3. **Process Lifetime Boundary:** The in-memory queue exists solely for the lifetime of the process.
 *    If the process dies while encryption remains unavailable, the queued notifications are lost.
 *    This data loss is an intentional security trade-off: losing temporary notification events is
 *    far preferable to persisting unencrypted financial PII on disk.
 * 4. **Atomic Non-Destructive Self-Healing Flush:** As soon as encrypted storage becomes available
 *    again, all in-memory queued notifications are atomically flushed to `EncryptedSharedPreferences`
 *    using a non-destructive peek-and-commit pattern. Memory queue items are polled ONLY AFTER disk
 *    write commit succeeds, guaranteeing zero notification loss on I/O or encryption failures.
 */
object EncryptedNotificationCache {

    private const val TAG = "EncryptedNotifCache"
    private const val LEGACY_PREF_NAME = "pet_notification_cache"
    private const val FALLBACK_PREF_NAME = "pet_notification_cache_v2_fallback"
    private const val ENCRYPTED_PREF_NAME = "pet_notification_cache_v2"
    private const val KEY_PENDING = "pending_notifications"

    /**
     * Maximum capacity for the in-memory fallback queue.
     * Prevents unbounded heap memory growth (OOM) during prolonged Keystore outages.
     * 200 notifications (~300 KB RAM) provides ample headroom for notification bursts.
     */
    const val MAX_IN_MEMORY_CAPACITY = 200

    @Volatile
    private var isMigrated = false

    /**
     * In-memory queue for buffering notifications when EncryptedSharedPreferences is unavailable.
     * Thread-safe, bounded, and RAM-only.
     */
    private val inMemoryQueue: Queue<Map<String, Any?>> = ConcurrentLinkedQueue()

    /**
     * Custom supplier / factory for EncryptedSharedPreferences to allow injection in unit tests.
     */
    @VisibleForTesting
    var encryptedPrefsFactory: ((Context) -> SharedPreferences)? = null

    /**
     * Obtain an EncryptedSharedPreferences instance safely.
     * On Keystore corruption or decryption failure, attempts to reset and recreate the encrypted store.
     *
     * SECURITY GUARANTEE:
     * Returns null if EncryptedSharedPreferences cannot be initialized.
     * NEVER falls back to unencrypted plaintext SharedPreferences.
     */
    @Synchronized
    fun getPrefs(context: Context): SharedPreferences? {
        val prefs = try {
            encryptedPrefsFactory?.invoke(context) ?: createEncryptedPrefs(context)
        } catch (e: Exception) {
            SafeLog.w(TAG, "Keystore or EncryptedSharedPreferences error: ${e.message}. Resetting store.")
            resetEncryptedPrefs(context)
            try {
                encryptedPrefsFactory?.invoke(context) ?: createEncryptedPrefs(context)
            } catch (e2: Exception) {
                SafeLog.e(TAG, "EncryptedSharedPreferences creation failed after reset: ${e2.message}. DISK PERSISTENCE DISABLED.")
                null
            }
        }

        if (prefs != null) {
            // Perform one-time migration of legacy plaintext caches (if any exist from older app versions)
            if (!isMigrated) {
                migrateLegacyPlaintext(context, prefs)
                isMigrated = true
            }
            // Flush any in-memory queued notifications into encrypted storage
            flushInMemoryQueueLocked(prefs)
        }

        return prefs
    }

    private fun createEncryptedPrefs(context: Context): SharedPreferences {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()

        return EncryptedSharedPreferences.create(
            context,
            ENCRYPTED_PREF_NAME,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    }

    private fun resetEncryptedPrefs(context: Context) {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                context.deleteSharedPreferences(ENCRYPTED_PREF_NAME)
            } else {
                context.getSharedPreferences(ENCRYPTED_PREF_NAME, Context.MODE_PRIVATE).edit().clear().apply()
            }
            SafeLog.i(TAG, "Successfully cleared corrupted encrypted SharedPreferences file.")
        } catch (e: Exception) {
            SafeLog.e(TAG, "Failed to delete corrupted prefs: ${e.message}")
        }
    }

    /**
     * Migrate existing legacy plaintext caches (`pet_notification_cache` and `pet_notification_cache_v2_fallback`)
     * to the encrypted store, then securely delete the plaintext files from disk.
     */
    @Synchronized
    fun migrateLegacyPlaintext(context: Context, encryptedPrefs: SharedPreferences) {
        val legacyFiles = listOf(LEGACY_PREF_NAME, FALLBACK_PREF_NAME)

        for (prefName in legacyFiles) {
            try {
                val legacyPrefs = context.getSharedPreferences(prefName, Context.MODE_PRIVATE)
                val legacyJsonString = legacyPrefs.getString(KEY_PENDING, null)

                if (!legacyJsonString.isNullOrEmpty() && legacyJsonString != "[]") {
                    val legacyArray = JSONArray(legacyJsonString)
                    if (legacyArray.length() > 0) {
                        val existingJsonString = encryptedPrefs.getString(KEY_PENDING, "[]") ?: "[]"
                        val existingArray = JSONArray(existingJsonString)

                        for (i in 0 until legacyArray.length()) {
                            existingArray.put(legacyArray.getJSONObject(i))
                        }

                        val committed = encryptedPrefs.edit().putString(KEY_PENDING, existingArray.toString()).commit()
                        if (committed) {
                            SafeLog.i(TAG, "Migrated ${legacyArray.length()} notifications from legacy plaintext store '$prefName' to encrypted store.")
                        }
                    }
                }

                // Clear data and delete legacy plaintext file from disk
                legacyPrefs.edit().clear().commit()
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                    context.deleteSharedPreferences(prefName)
                }
            } catch (e: Exception) {
                SafeLog.e(TAG, "Error migrating legacy plaintext cache '$prefName': ${e.message}")
            }
        }
    }

    /**
     * Flushes buffered in-memory notifications into EncryptedSharedPreferences atomically.
     *
     * ATOMIC FLUSH ALGORITHM (Non-destructive peek-and-commit):
     * 1. Takes a non-destructive snapshot of the queue (`inMemoryQueue.toList()`).
     * 2. Deserializes existing encrypted cache and appends snapshot items to JSON.
             * 3. Commits to disk synchronously using `.commit()`.
     * 4. ONLY AFTER disk commit succeeds, polls exactly `snapshot.size` items from `inMemoryQueue`.
     * 5. If commit fails or throws an exception, `inMemoryQueue` remains completely intact in RAM.
     */
    private fun flushInMemoryQueueLocked(encryptedPrefs: SharedPreferences) {
        if (inMemoryQueue.isEmpty()) return

        try {
            val snapshot = inMemoryQueue.toList()
            if (snapshot.isEmpty()) return

            val cachedString = encryptedPrefs.getString(KEY_PENDING, "[]") ?: "[]"
            val jsonArray = JSONArray(cachedString)

            for (item in snapshot) {
                val jsonObject = JSONObject()
                for ((key, value) in item) {
                    jsonObject.put(key, value)
                }
                jsonArray.put(jsonObject)
            }

            val commitSuccess = encryptedPrefs.edit().putString(KEY_PENDING, jsonArray.toString()).commit()

            if (commitSuccess) {
                // Disk commit succeeded: safely pop snapshot count from queue head
                for (i in snapshot.indices) {
                    inMemoryQueue.poll()
                }
                SafeLog.i(TAG, "Successfully flushed ${snapshot.size} in-memory buffered notifications into encrypted storage.")
            } else {
                SafeLog.e(TAG, "Disk commit returned false during flush. In-memory queue preserved (${inMemoryQueue.size} items).")
            }
        } catch (e: Exception) {
            SafeLog.e(TAG, "Failed to flush in-memory queue to encrypted storage: ${e.message}. Queue preserved.")
        }
    }

    /**
     * Buffers a notification payload into the in-memory queue, enforcing capacity bounds.
     */
    private fun enqueueInMemory(data: Map<String, Any?>) {
        while (inMemoryQueue.size >= MAX_IN_MEMORY_CAPACITY) {
            val evicted = inMemoryQueue.poll()
            if (evicted != null) {
                SafeLog.w(TAG, "InMemoryQueue capacity limit reached ($MAX_IN_MEMORY_CAPACITY). Evicted oldest notification to prevent OOM.")
            }
        }
        inMemoryQueue.add(data)
    }

    /**
     * Save a notification payload map to cache.
     *
     * Behavior:
     * 1. If EncryptedSharedPreferences is operational:
     *    - Flushes any pending in-memory notifications first (preserving order).
     *    - Persists the new notification payload to encrypted disk storage via atomic commit.
     * 2. If EncryptedSharedPreferences is unavailable (Keystore error):
     *    - Buffers notification in-memory ONLY (bounded to MAX_IN_MEMORY_CAPACITY).
     *    - Never writes plaintext to disk.
     */
    @Synchronized
    fun saveNotification(context: Context, data: Map<String, Any?>) {
        try {
            val prefs = getPrefs(context)
            if (prefs != null) {
                val cachedString = prefs.getString(KEY_PENDING, "[]") ?: "[]"
                val jsonArray = JSONArray(cachedString)

                val jsonObject = JSONObject()
                for ((key, value) in data) {
                    jsonObject.put(key, value)
                }
                jsonArray.put(jsonObject)

                val commitSuccess = prefs.edit().putString(KEY_PENDING, jsonArray.toString()).commit()
                if (commitSuccess) {
                    SafeLog.d(TAG, "Safely saved notification to encrypted cache. Total cached: ${jsonArray.length()}")
                } else {
                    SafeLog.w(TAG, "Failed to commit notification to EncryptedSharedPreferences. Buffering in RAM.")
                    enqueueInMemory(data)
                }
            } else {
                // Encrypted storage unavailable: buffer in memory strictly for process lifetime
                enqueueInMemory(data)
                SafeLog.w(TAG, "EncryptedSharedPreferences unavailable. Notification buffered in RAM only (total in-memory: ${inMemoryQueue.size}).")
            }
        } catch (e: Exception) {
            SafeLog.e(TAG, "Error saving notification: ${e.message}. Fallback to in-memory buffering.")
            enqueueInMemory(data)
        }
    }

    /**
     * Retrieve and clear all pending cached notifications.
     *
     * Preserves strict FIFO insertion order across in-memory queue and encrypted storage.
     */
    @Synchronized
    fun popPendingNotifications(context: Context): List<Map<String, Any?>> {
        val results = mutableListOf<Map<String, Any?>>()
        try {
            val prefs = getPrefs(context)
            if (prefs != null) {
                // getPrefs() automatically flushed inMemoryQueue into prefs
                val cachedString = prefs.getString(KEY_PENDING, "[]") ?: "[]"
                val jsonArray = JSONArray(cachedString)

                if (jsonArray.length() > 0) {
                    SafeLog.d(TAG, "Processing ${jsonArray.length()} cached notifications from encrypted store")
                    for (i in 0 until jsonArray.length()) {
                        val jsonObject = jsonArray.getJSONObject(i)
                        val data = mutableMapOf<String, Any?>()
                        val keys = jsonObject.keys()
                        while (keys.hasNext()) {
                            val key = keys.next()
                            data[key] = jsonObject.get(key)
                        }
                        results.add(data)
                    }
                    // Clear the encrypted cache after popping
                    prefs.edit().putString(KEY_PENDING, "[]").commit()
                }
            } else {
                // Encrypted storage unavailable: drain and return in-memory queue
                if (inMemoryQueue.isNotEmpty()) {
                    SafeLog.d(TAG, "Processing ${inMemoryQueue.size} in-memory buffered notifications (encrypted store unavailable)")
                    while (true) {
                        val item = inMemoryQueue.poll() ?: break
                        results.add(item)
                    }
                }
            }
        } catch (e: Exception) {
            SafeLog.e(TAG, "Error popping notifications: ${e.message}")
            while (true) {
                val item = inMemoryQueue.poll() ?: break
                results.add(item)
            }
        }
        return results
    }

    /**
     * Visible for testing only: Returns current in-memory queue size.
     */
    @VisibleForTesting
    fun getInMemoryQueueSizeForTesting(): Int = inMemoryQueue.size

    /**
     * Visible for testing only: Clears in-memory queue and resets state.
     */
    @VisibleForTesting
    fun resetForTesting() {
        inMemoryQueue.clear()
        isMigrated = false
        encryptedPrefsFactory = null
    }
}
