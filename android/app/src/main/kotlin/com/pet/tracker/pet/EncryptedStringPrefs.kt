package com.pet.tracker.pet

import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Encrypts and decrypts short strings. [aad] binds a ciphertext to its key name. */
interface StringCipher {
    fun encrypt(plain: String, aad: String): String
    fun decrypt(token: String, aad: String): String
}

/**
 * AES-256-GCM with a non-exportable key in the Android Keystore. Replaces the
 * deprecated Jetpack `security-crypto` library for the notification cache.
 *
 * Token format: `v1:` + Base64(12-byte IV ‖ ciphertext with 128-bit tag).
 */
class KeystoreStringCipher(private val alias: String) : StringCipher {

    private fun keyStore(): KeyStore =
        KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }

    private fun key(): SecretKey {
        (keyStore().getKey(alias, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(
                alias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return generator.generateKey()
    }

    override fun encrypt(plain: String, aad: String): String {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key())
        cipher.updateAAD(aad.toByteArray(Charsets.UTF_8))
        val sealed = cipher.iv + cipher.doFinal(plain.toByteArray(Charsets.UTF_8))
        return PREFIX + Base64.encodeToString(sealed, Base64.NO_WRAP)
    }

    override fun decrypt(token: String, aad: String): String {
        require(token.startsWith(PREFIX)) { "Unknown token format" }
        val sealed = Base64.decode(token.removePrefix(PREFIX), Base64.NO_WRAP)
        require(sealed.size > IV_BYTES) { "Token too short" }
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(
            Cipher.DECRYPT_MODE,
            key(),
            GCMParameterSpec(TAG_BITS, sealed, 0, IV_BYTES)
        )
        cipher.updateAAD(aad.toByteArray(Charsets.UTF_8))
        return String(cipher.doFinal(sealed, IV_BYTES, sealed.size - IV_BYTES), Charsets.UTF_8)
    }

    /** Deletes the key (the store is unreadable after this; used on reset). */
    fun deleteKey() {
        try {
            keyStore().deleteEntry(alias)
        } catch (_: Exception) {
        }
    }

    private companion object {
        const val ANDROID_KEYSTORE = "AndroidKeyStore"
        const val TRANSFORMATION = "AES/GCM/NoPadding"
        const val PREFIX = "v1:"
        const val IV_BYTES = 12
        const val TAG_BITS = 128
    }
}

/**
 * [SharedPreferences] whose string values are encrypted at rest with
 * [cipher]. Only `getString` / `putString` are transformed, which is all the
 * notification cache uses; other value types are stored as given.
 *
 * Reading a value that fails to decrypt (lost key, tampering) throws, so the
 * caller can reset the store instead of silently returning nothing.
 */
class EncryptedStringPrefs(
    private val backing: SharedPreferences,
    private val cipher: StringCipher
) : SharedPreferences by backing {

    override fun getString(key: String, defValue: String?): String? {
        val stored = backing.getString(key, null) ?: return defValue
        return cipher.decrypt(stored, key)
    }

    override fun edit(): SharedPreferences.Editor = Editor(backing.edit())

    private inner class Editor(
        private val delegate: SharedPreferences.Editor
    ) : SharedPreferences.Editor by delegate {
        override fun putString(key: String, value: String?): SharedPreferences.Editor {
            if (value == null) delegate.remove(key) else delegate.putString(key, cipher.encrypt(value, key))
            return this
        }

        override fun remove(key: String): SharedPreferences.Editor {
            delegate.remove(key)
            return this
        }

        override fun clear(): SharedPreferences.Editor {
            delegate.clear()
            return this
        }
    }
}
