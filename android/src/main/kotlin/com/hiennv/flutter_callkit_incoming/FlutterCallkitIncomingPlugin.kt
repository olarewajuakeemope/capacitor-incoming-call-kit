package com.hiennv.flutter_callkit_incoming

import android.annotation.SuppressLint
import android.app.Activity
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.NonNull
import com.beust.klaxon.JsonObject
import com.beust.klaxon.Klaxon
import com.beust.klaxon.Parser
import com.getcapacitor.JSArray
import com.getcapacitor.JSObject;
import com.getcapacitor.Logger;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.hiennv.flutter_callkit_incoming.Utils.Companion.reapCollection
import org.json.JSONObject
import java.lang.ref.WeakReference

/** FlutterCallkitIncomingPlugin */
@CapacitorPlugin(name = "FlutterCallkitIncoming")
class FlutterCallkitIncomingPlugin : Plugin() {
    companion object {

        const val EXTRA_CALLKIT_CALL_DATA = "EXTRA_CALLKIT_CALL_DATA"

        @SuppressLint("StaticFieldLeak")
        private lateinit var instance: FlutterCallkitIncomingPlugin

        public fun getInstance(): FlutterCallkitIncomingPlugin {
            return instance
        }

        public fun hasInstance(): Boolean {
            return ::instance.isInitialized
        }


        fun sharePluginWithRegister(activity: Activity, pluginInstance: FlutterCallkitIncomingPlugin) {
            initSharedInstance(activity.applicationContext, pluginInstance)
        }

        fun initSharedInstance(context: Context, pluginInstance: FlutterCallkitIncomingPlugin) {
            if (!::instance.isInitialized) {
                instance = pluginInstance
                instance.callkitNotificationManager = CallkitNotificationManager(context)
                instance.context = context
            }
        }

        fun sendEvent(event: String, mapBody: Map<String, Any>) {
            val body = JSObject()
            for ((key, value) in mapBody) {
                body.put(key, value)
            }
            this.getInstance().notifyListeners(event, body)
        }

        public fun sendEventCustom(event: String, mapBody: Map<String, Any>) {
            val body = JSObject()
            for ((key, value) in mapBody) {
                body.put(key, value)
            }
            this.getInstance().notifyListeners(event, body)
        }

    }

    /// The MethodChannel that will the communication between Flutter and native Android
    ///
    /// This local reference serves to register the plugin with the Flutter Engine and unregister it
    /// when the Flutter Engine is detached from the Activity
    private var activity: Activity? = null
    private var context: Context? = null
    private var callkitNotificationManager: CallkitNotificationManager? = null

    override fun load() {
        activity = this.getBridge().activity
        context = this.getBridge().activity.applicationContext
        callkitNotificationManager = CallkitNotificationManager(this.getBridge().activity.applicationContext)
        sharePluginWithRegister(this.getBridge().activity, this)
    }

    fun listToJSList(list: ArrayList<Map<String, Any?>>): JSArray {
        val jsArray = JSArray()
        for (item in list) {
            val jsObject = JSObject()
            for ((key, value) in item) {
                jsObject.put(key, value)
            }
            jsArray.put(jsObject)
        }
        return jsArray
    }

    public fun showIncomingNotification(data: Data) {
        data.from = "notification"
        callkitNotificationManager?.showIncomingNotification(data.toBundle())
        //send BroadcastReceiver
        context?.sendBroadcast(
                CallkitIncomingBroadcastReceiver.getIntentIncoming(
                        requireNotNull(context),
                        data.toBundle()
                )
        )
    }

    public fun showMissCallNotification(data: Data) {
        callkitNotificationManager?.showIncomingNotification(data.toBundle())
    }

    public fun startCall(data: Data) {
        context?.sendBroadcast(
                CallkitIncomingBroadcastReceiver.getIntentStart(
                        requireNotNull(context),
                        data.toBundle()
                )
        )
    }

    public fun endCall(data: Data) {
        context?.sendBroadcast(
                CallkitIncomingBroadcastReceiver.getIntentEnded(
                        requireNotNull(context),
                        data.toBundle()
                )
        )
    }

    public fun endAllCalls() {
        val calls = getDataActiveCalls(context)
        calls.forEach {
            context?.sendBroadcast(
                    CallkitIncomingBroadcastReceiver.getIntentEnded(
                            requireNotNull(context),
                            it.toBundle()
                    )
            )
        }
        removeAllCalls(context)
    }

    public fun sendEventCustom(mapBody: Map<String, Any>) {
        val body = JSObject()
        for ((key, value) in mapBody) {
            body.put(key, value)
        }
        notifyListeners(CallkitConstants.ACTION_CALL_CUSTOM, body)
    }

    @PluginMethod
    public fun onMethod(call: PluginCall) {
        try {
            val parser: Parser = Parser.default()
            val name: String = call.getString("methodName")!!
            val ojsString: String = call.getString("options")!!
            val ojsJsonObject = parser.parse(StringBuilder(ojsString)) as JsonObject
            val options = ojsJsonObject.toMutableMap()
            for ((key, value) in options) {
                if (value is JsonObject) {
                    options[key] = value.toMutableMap()
                }
            }
            when (name) {
                "showCallkitIncoming" -> {
                    val data = Data(options ?: HashMap())
                    data.from = "notification"
                    //send BroadcastReceiver
                    context?.sendBroadcast(
                            CallkitIncomingBroadcastReceiver.getIntentIncoming(
                                    requireNotNull(context),
                                    data.toBundle()
                            )
                    )
                    call.resolve()
                }

                "showCallkitIncomingSilently" -> {
                    val data = Data(options ?: HashMap())
                    data.from = "notification"

                    call.resolve()
                }

                "showMissCallNotification" -> {
                    val data = Data(options ?: HashMap())
                    data.from = "notification"
                    callkitNotificationManager?.showMissCallNotification(data.toBundle())
                    call.resolve()
                }

                "startCall" -> {
                    val data = Data(options ?: HashMap())
                    context?.sendBroadcast(
                            CallkitIncomingBroadcastReceiver.getIntentStart(
                                    requireNotNull(context),
                                    data.toBundle()
                            )
                    )

                    call.resolve()
                }

                "muteCall" -> {
                    val map = buildMap {
                        val args = options
                        if (args is Map<*, *>) {
                            putAll(args as Map<String, Any>)
                        }
                    }
                    sendEvent(CallkitConstants.ACTION_CALL_TOGGLE_MUTE, map)

                    call.resolve()
                }

                "holdCall" -> {
                    val map = buildMap {
                        val args = options
                        if (args is Map<*, *>) {
                            putAll(args as Map<String, Any>)
                        }
                    }
                    sendEvent(CallkitConstants.ACTION_CALL_TOGGLE_HOLD, map)

                    call.resolve()
                }

                "isMuted" -> {
                    call.resolve()
                }

                "endCall" -> {
                    val data = Data(options ?: HashMap())
                    context?.sendBroadcast(
                            CallkitIncomingBroadcastReceiver.getIntentEnded(
                                    requireNotNull(context),
                                    data.toBundle()
                            )
                    )

                    call.resolve()
                }

                "callConnected" -> {
                    call.resolve()
                }

                "endAllCalls" -> {
                    val calls = getDataActiveCalls(context)
                    calls.forEach {
                        if (it.isAccepted) {
                            context?.sendBroadcast(
                                    CallkitIncomingBroadcastReceiver.getIntentEnded(
                                            requireNotNull(context),
                                            it.toBundle()
                                    )
                            )
                        } else {
                            context?.sendBroadcast(
                                    CallkitIncomingBroadcastReceiver.getIntentDecline(
                                            requireNotNull(context),
                                            it.toBundle()
                                    )
                            )
                        }
                    }
                    removeAllCalls(context)
                    call.resolve()
                }

                "activeCalls" -> {
                    val calls = listToJSList(getDataActiveCallsForFlutter(context))
                    val jsObject = JSObject()
                    jsObject.put("calls", calls)
                     call.resolve(jsObject)
                }

                "getDevicePushTokenVoIP" -> {
                    call.resolve()
                }

                "silenceEvents" -> {
                    val silence = options as? Boolean ?: false
                    CallkitIncomingBroadcastReceiver.silenceEvents = silence
                    call.resolve()
                }

                "requestNotificationPermission" -> {
                    val map = buildMap {
                        val args = options
                        if (args is Map<*, *>) {
                            putAll(args as Map<String, Any>)
                        }
                    }
                    callkitNotificationManager?.requestNotificationPermission(activity, map)
                }
                "requestFullIntentPermission" -> {
                    callkitNotificationManager?.requestFullIntentPermission(activity)
                }
                // EDIT - clear the incoming notification/ring (after accept/decline/timeout)
                "hideCallkitIncoming" -> {
                    val data = Data(options ?: HashMap())
                    context?.stopService(Intent(context, CallkitSoundPlayerService::class.java))
                    callkitNotificationManager?.clearIncomingNotification(data.toBundle(), false)
                }

                "endNativeSubsystemOnly" -> {

                }

                "setAudioRoute" -> {

                }
            }
        } catch (error: Exception) {
            call.reject(error.message)
        }
    }

    fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray): Boolean {
        callkitNotificationManager?.onRequestPermissionsResult(activity, requestCode, grantResults)
        return true
    }
}
