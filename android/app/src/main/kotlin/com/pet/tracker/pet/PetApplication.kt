package com.pet.tracker.pet

import android.app.Application
import com.pet.tracker.enginehooks.EngineHooksPlugin

class PetApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // Attach the native SMS / notification plugin to every Flutter
        // engine, including WorkManager's background engines. Adding it only
        // in MainActivity left background scans and notification processing
        // without the channel (MissingPluginException → nothing imported).
        EngineHooksPlugin.registerPluginFactory { SmsReaderPlugin() }
    }
}
