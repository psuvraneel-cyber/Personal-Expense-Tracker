package com.pet.tracker.enginehooks

import io.flutter.embedding.engine.plugins.FlutterPlugin
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Attaches app-defined plugins to every Flutter engine.
 *
 * Engines created outside an Activity (WorkManager's `BackgroundWorker`,
 * notification-action isolates) only receive the plugins listed in
 * `GeneratedPluginRegistrant`. Plugins that live in the app module are not
 * listed there, so their channels are missing in those engines and every
 * call fails with `MissingPluginException`.
 *
 * This plugin is listed there. The app registers its plugin factories once in
 * `Application.onCreate` (which runs before any engine is created in the
 * process); each engine then gets fresh plugin instances, attached and
 * detached together with this plugin.
 */
class EngineHooksPlugin : FlutterPlugin {

    companion object {
        private val factories = CopyOnWriteArrayList<() -> FlutterPlugin>()

        /** Registers a factory whose plugin is attached to every engine created afterwards. */
        @JvmStatic
        fun registerPluginFactory(factory: () -> FlutterPlugin) {
            factories.add(factory)
        }

        /** Visible for testing: removes all registered factories. */
        @JvmStatic
        fun clearPluginFactoriesForTesting() {
            factories.clear()
        }
    }

    private val attached = mutableListOf<FlutterPlugin>()

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        for (factory in factories) {
            val plugin = factory()
            plugin.onAttachedToEngine(binding)
            attached.add(plugin)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        for (plugin in attached) {
            plugin.onDetachedFromEngine(binding)
        }
        attached.clear()
    }
}
