package com.pet.tracker.pet

import android.content.Context
import android.util.Base64
import androidx.test.core.app.ApplicationProvider
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * The Android Keystore isn't available on the JVM, so these tests use the
 * same AES-256-GCM scheme with an in-memory key.
 */
private class JvmAesGcmCipher(private val key: SecretKey = newKey()) : StringCipher {
    override fun encrypt(plain: String, aad: String): String {
        val iv = ByteArray(12).also { SecureRandom().nextBytes(it) }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(128, iv))
        cipher.updateAAD(aad.toByteArray())
        return "v1:" + Base64.encodeToString(iv + cipher.doFinal(plain.toByteArray()), Base64.NO_WRAP)
    }

    override fun decrypt(token: String, aad: String): String {
        val sealed = Base64.decode(token.removePrefix("v1:"), Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, sealed, 0, 12))
        cipher.updateAAD(aad.toByteArray())
        return String(cipher.doFinal(sealed, 12, sealed.size - 12))
    }

    companion object {
        fun newKey(): SecretKey = KeyGenerator.getInstance("AES").apply { init(256) }.generateKey()
    }
}

@RunWith(RobolectricTestRunner::class)
class EncryptedStringPrefsTest {

    private lateinit var context: Context

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        context.getSharedPreferences("enc_test", Context.MODE_PRIVATE).edit().clear().commit()
    }

    private fun backing() = context.getSharedPreferences("enc_test", Context.MODE_PRIVATE)

    @Test
    fun `values round-trip and are not stored in plaintext`() {
        val prefs = EncryptedStringPrefs(backing(), JvmAesGcmCipher())
        val payload = """[{"title":"HDFC","body":"Rs 450 debited"}]"""

        assertTrue(prefs.edit().putString("pending", payload).commit())

        assertEquals(payload, prefs.getString("pending", null))
        val raw = backing().getString("pending", null)!!
        assertTrue(raw.startsWith("v1:"))
        assertFalse(raw.contains("HDFC"))
        assertFalse(raw.contains("450"))
    }

    @Test
    fun `missing values return the default`() {
        val prefs = EncryptedStringPrefs(backing(), JvmAesGcmCipher())
        assertEquals("[]", prefs.getString("pending", "[]"))
        assertNull(prefs.getString("pending", null))
    }

    @Test
    fun `remove and clear delete values`() {
        val prefs = EncryptedStringPrefs(backing(), JvmAesGcmCipher())
        prefs.edit().putString("a", "1").putString("b", "2").commit()
        prefs.edit().remove("a").commit()
        assertNull(prefs.getString("a", null))
        prefs.edit().clear().commit()
        assertNull(prefs.getString("b", null))
    }

    @Test
    fun `a value from another key or a lost key fails to read`() {
        val prefs = EncryptedStringPrefs(backing(), JvmAesGcmCipher())
        prefs.edit().putString("pending", "secret").commit()

        // Moved to another key name: the AAD no longer matches.
        backing().edit().putString("other", backing().getString("pending", null)).commit()
        try {
            prefs.getString("other", null)
            fail("expected decryption to fail")
        } catch (expected: Exception) {
        }

        // Read with a different key (e.g. the Keystore key was lost).
        val withNewKey = EncryptedStringPrefs(backing(), JvmAesGcmCipher())
        try {
            withNewKey.getString("pending", null)
            fail("expected decryption to fail")
        } catch (expected: Exception) {
        }
    }

    @Test
    fun `the notification cache works on top of it`() {
        EncryptedNotificationCache.resetForTesting()
        val cipher = JvmAesGcmCipher()
        EncryptedNotificationCache.encryptedPrefsFactory = { EncryptedStringPrefs(backing(), cipher) }
        try {
            EncryptedNotificationCache.saveNotification(
                context,
                mapOf("title" to "HDFC Bank", "body" to "Rs 820 debited", "date" to System.currentTimeMillis())
            )
            val pending = EncryptedNotificationCache.peekPendingNotifications(context)
            assertEquals(1, pending.size)
            assertEquals("HDFC Bank", pending.single()["title"])
            assertFalse(backing().getString("pending_notifications", null)!!.contains("HDFC"))
        } finally {
            EncryptedNotificationCache.resetForTesting()
        }
    }
}
