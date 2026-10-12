package com.pet.tracker.pet

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.pet.tracker.enginehooks.EngineHooksPlugin
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.kotlin.any
import org.mockito.kotlin.anyOrNull
import org.mockito.kotlin.atLeast
import org.mockito.kotlin.doReturn
import org.mockito.kotlin.mock
import org.mockito.kotlin.verify
import org.robolectric.RobolectricTestRunner

/**
 * The native plugin must be attached to every Flutter engine (UI and
 * WorkManager background engines), and one engine shutting down must not
 * disconnect another engine's live listeners.
 */
@RunWith(RobolectricTestRunner::class)
class BackgroundEnginePluginTest {

    private lateinit var context: Context

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        EngineHooksPlugin.clearPluginFactoriesForTesting()
        SmsReaderPlugin.eventSink = null
        TransactionNotificationListener.resetForTesting()
    }

    @After
    fun tearDown() {
        EngineHooksPlugin.clearPluginFactoriesForTesting()
        SmsReaderPlugin.eventSink = null
        TransactionNotificationListener.resetForTesting()
    }

    private fun engineBinding(): FlutterPlugin.FlutterPluginBinding {
        val messenger = mock<BinaryMessenger>()
        return mock {
            on { binaryMessenger } doReturn messenger
            on { applicationContext } doReturn context
        }
    }

    private class RecordingPlugin : FlutterPlugin {
        val attachedTo = mutableListOf<FlutterPlugin.FlutterPluginBinding>()
        val detachedFrom = mutableListOf<FlutterPlugin.FlutterPluginBinding>()
        override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
            attachedTo.add(binding)
        }
        override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
            detachedFrom.add(binding)
        }
    }

    @Test
    fun applicationRegistersSmsReaderPluginForEveryEngine() {
        PetApplication().onCreate()
        val hooks = EngineHooksPlugin()
        val binding = engineBinding()

        hooks.onAttachedToEngine(binding)

        // The method channel and both event channels were set up on this
        // engine's messenger.
        verify(binding.binaryMessenger, atLeast(3)).setMessageHandler(any(), anyOrNull())
        hooks.onDetachedFromEngine(binding)
    }

    @Test
    fun eachEngineGetsItsOwnPluginInstance() {
        val created = mutableListOf<RecordingPlugin>()
        EngineHooksPlugin.registerPluginFactory { RecordingPlugin().also { created.add(it) } }

        val uiBinding = engineBinding()
        val bgBinding = engineBinding()
        val uiHooks = EngineHooksPlugin().apply { onAttachedToEngine(uiBinding) }
        val bgHooks = EngineHooksPlugin().apply { onAttachedToEngine(bgBinding) }

        assertEquals(2, created.size)
        assertEquals(listOf(uiBinding), created[0].attachedTo)
        assertEquals(listOf(bgBinding), created[1].attachedTo)

        bgHooks.onDetachedFromEngine(bgBinding)
        assertEquals(listOf(bgBinding), created[1].detachedFrom)
        assertTrue("UI engine's plugin must stay attached", created[0].detachedFrom.isEmpty())

        uiHooks.onDetachedFromEngine(uiBinding)
        assertEquals(listOf(uiBinding), created[0].detachedFrom)
    }

    @Test
    fun backgroundEngineDetachKeepsUiSmsSink() {
        val uiSink = mock<EventChannel.EventSink>()
        val uiPlugin = SmsReaderPlugin().apply { onAttachedToEngine(engineBinding()) }
        uiPlugin.onListen(null, uiSink)

        val bgBinding = engineBinding()
        val bgPlugin = SmsReaderPlugin().apply { onAttachedToEngine(bgBinding) }
        bgPlugin.onDetachedFromEngine(bgBinding)

        assertSame(uiSink, SmsReaderPlugin.eventSink)
    }

    @Test
    fun backgroundEngineDetachKeepsUiNotificationSink() {
        val uiSink = mock<EventChannel.EventSink>()
        TransactionNotificationListener.eventSink = uiSink

        val bgBinding = engineBinding()
        val bgPlugin = SmsReaderPlugin().apply { onAttachedToEngine(bgBinding) }
        bgPlugin.onDetachedFromEngine(bgBinding)

        assertSame(uiSink, TransactionNotificationListener.eventSink)
    }

    @Test
    fun detachingTheListeningEngineClearsItsSmsSink() {
        // Otherwise SmsBroadcastReceiver keeps posting to a dead engine and
        // never schedules the background scan.
        val binding = engineBinding()
        val plugin = SmsReaderPlugin().apply { onAttachedToEngine(binding) }
        plugin.onListen(null, mock<EventChannel.EventSink>())

        plugin.onDetachedFromEngine(binding)

        assertNull(SmsReaderPlugin.eventSink)
    }

    @Test
    fun cancelOnlyClearsTheCancellingEnginesSink() {
        val oldSink = mock<EventChannel.EventSink>()
        val newSink = mock<EventChannel.EventSink>()
        val oldPlugin = SmsReaderPlugin().apply { onAttachedToEngine(engineBinding()) }
        val newPlugin = SmsReaderPlugin().apply { onAttachedToEngine(engineBinding()) }
        oldPlugin.onListen(null, oldSink)
        newPlugin.onListen(null, newSink)

        oldPlugin.onCancel(null)
        assertSame(newSink, SmsReaderPlugin.eventSink)

        newPlugin.onCancel(null)
        assertNull(SmsReaderPlugin.eventSink)
    }

    @Test
    fun clearingTheNotificationSinkAdvancesTheVersion() {
        val sink = mock<EventChannel.EventSink>()
        TransactionNotificationListener.eventSink = sink
        val before = TransactionNotificationListener.getSinkVersionForTesting()

        TransactionNotificationListener.clearEventSinkIf(mock())
        assertSame(sink, TransactionNotificationListener.eventSink)
        assertEquals(before, TransactionNotificationListener.getSinkVersionForTesting())

        TransactionNotificationListener.clearEventSinkIf(sink)
        assertNull(TransactionNotificationListener.eventSink)
        assertEquals(before + 1, TransactionNotificationListener.getSinkVersionForTesting())
    }
}
