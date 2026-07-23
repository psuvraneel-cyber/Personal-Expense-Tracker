package com.pet.tracker.pet

import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import org.json.JSONArray
import org.json.JSONObject

/**
 * Production-ready encrypted storage for pending transaction notifications.
 *
 * ## Security Architecture:
 * - Uses Jetpack Security Crypto (`EncryptedSharedPreferences` + `MasterKey` AES256_GCM).
 * - Stores pending notification payloads at `pet_notification_cache_v2`.
 * - Migrates legacy plaintext `pet_notification_cache` data on first launch and deletes old file.
 * - Handles Keystore invalidation / corruption gracefully without crashing.
 */
object EncryptedNotificationCache {

    private const val TAG = "EncryptedNotifCache"
    private const val LEGACY_PREF_NAME = "pet_notification_cache"
    private const val ENCRYPTED_PREF_NAME = "pet_notification_cache_v2"
    private const val KEY_PENDING = "pending_notifications"

    @Volatile
    private var isMigrated = false

    /**
     * Obtain an EncryptedSharedPreferences instance safely.
     * On Keystore corruption or decryption failure, clears and recreates the store.
     */
    @Synchronized
    fun getPrefs(context: Context): SharedPreferences {
        val prefs = try {
            createEncryptedPrefs(context)
        } catch (e: Exception) {
            SafeLog.w(TAG, "Keystore or EncryptedSharedPreferences error: ${e.message}. Resetting store.")
            resetEncryptedPrefs(context)
            try {
                createEncryptedPrefs(context)
            } catch (e2: Exception) {
                SafeLog.e(TAG, "Fallback EncryptedSharedPreferences creation failed: ${e2.message}")
                // As absolute emergency fallback to prevent crashing, use private prefs
                context.getSharedPreferences("${ENCRYPTED_PREF_NAME}_fallback", Context.MODE_PRIVATE)
            }
        }

        // Perform one-time migration of legacy plaintext cache
        if (!isMigrated) {
            migrateLegacyPlaintext(context, prefs)
            isMigrated = true
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
        } catch (e: Exception) {
            SafeLog.e(TAG, "Failed to delete corrupted prefs: ${e.message}")
        }
    }

    /**
     * Migrate existing legacy plaintext `pet_notification_cache` to encrypted store.
     */
    @Synchronized
    fun migrateLegacyPlaintext(context: Context, encryptedPrefs: SharedPreferences) {
        try {
            val legacyPrefs = context.getSharedPreferences(LEGACY_PREF_NAME, Context.MODE_PRIVATE)
            val legacyJsonString = legacyPrefs.getString(KEY_PENDING, null)

            if (!legacyJsonString.isNull_or_empty() && legacyJsonString != "[]") {
                val legacyArray = JSONArray(legacyJsonString)
                if (legacyArray.length() > 0) {
                    val existingJsonString = encryptedPrefs.getString(KEY_PENDING, "[]") ?: "[]"
                    val existingArray = JSONArray(existingJsonString)

                    for (i in 0 until legacyArray.length()) {
                        existingArray.put(legacyArray.getJSONObject(i))
                    }

                    encryptedPrefs.edit().putString(KEY_PENDING, existingArray.toString()).apply()
                    SafeLog.i(TAG, "Migrated ${legacyArray.length()} legacy plaintext notifications to encrypted store")
                }
            }

            // Clear and delete legacy plaintext file
            legacyPrefs.edit().clear().apply()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                context.deleteSharedPreferences(LEGACY_PREF_NAME)
            }
        } catch (e: Exception) {
            SafeLog.e(TAG, "Error migrating legacy plaintext notification cache: ${e.message}")
        }
    }

    private fun String?.isNull_or_empty(): Boolean = this == null || this.isEmpty()

    /**
     * Save a notification payload map to the encrypted cache.
     */
    fun saveNotification(context: Context, data: Map<String, Any?>) {
        try {
            val prefs = getPrefs(context)
            val cachedString = prefs.getString(KEY_PENDING, "[]") ?: "[]"
            val jsonArray = JSONArray(cachedString)

            val jsonObject = JSONObject()
            for ((key, value) in data) {
                jsonObject.put(key, value)
            }
            jsonArray.put(jsonObject)

            prefs.edit().putString(KEY_PENDING, jsonArray.toString()).apply()
            SafeLog.d(TAG, "Safely saved notification to encrypted cache. Total cached: ${jsonArray.length()}")
        } catch (e: Exception) {
            SafeLog.e(TAG, "Failed to save notification to encrypted cache: ${e.message}")
        }
    }

    /**
     * Retrieve and clear all pending cached notifications from encrypted cache.
     */
    fun popPendingNotifications(context: Context): List<Map<String, Any?>> {
        val results = mutableListOf<Map<String, Any?>>()
        try {
            val prefs = getPrefs(context)
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
                // Clear the cache after popping
                prefs.edit().putString(KEY_PENDING, "[]").apply()
            }
        } catch (e: Exception) {
            SafeLog.e(TAG, "Error popping notifications from encrypted cache: ${e.message}")
        }
        return results
    }
}
