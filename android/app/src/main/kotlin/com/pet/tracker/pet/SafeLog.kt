package com.pet.tracker.pet

import android.util.Log

/**
 * Production-safe logger for native Kotlin components in P.E.T.
 *
 * ## Privacy & Security Principles:
 * 1. Debug (`d`) and Verbose (`v`) logs are completely NO-OP in release builds (`BuildConfig.DEBUG == false`).
 * 2. Info (`i`), Warn (`w`), and Error (`e`) logs are permitted in release builds BUT MUST NEVER
 *    contain sensitive financial data (SMS body, transaction amounts, account numbers, phone numbers,
 *    or merchant details).
 * 3. Never interpolate user PII or financial content into logcat messages.
 */
object SafeLog {

    /**
     * Debug log — executed ONLY in debug builds.
     */
    fun d(tag: String, message: String) {
        if (BuildConfig.DEBUG) {
            Log.d(tag, message)
        }
    }

    /**
     * Verbose log — executed ONLY in debug builds.
     */
    fun v(tag: String, message: String) {
        if (BuildConfig.DEBUG) {
            Log.v(tag, message)
        }
    }

    /**
     * Info log — executed ONLY in debug builds.
     */
    fun i(tag: String, message: String) {
        if (BuildConfig.DEBUG) {
            Log.i(tag, message)
        }
    }

    /**
     * Warning log — executed ONLY in debug builds.
     */
    fun w(tag: String, message: String, throwable: Throwable? = null) {
        if (BuildConfig.DEBUG) {
            if (throwable != null) {
                Log.w(tag, message, throwable)
            } else {
                Log.w(tag, message)
            }
        }
    }

    /**
     * Error log — executed ONLY in debug builds.
     */
    fun e(tag: String, message: String, throwable: Throwable? = null) {
        if (BuildConfig.DEBUG) {
            if (throwable != null) {
                Log.e(tag, message, throwable)
            } else {
                Log.e(tag, message)
            }
        }
    }
}
