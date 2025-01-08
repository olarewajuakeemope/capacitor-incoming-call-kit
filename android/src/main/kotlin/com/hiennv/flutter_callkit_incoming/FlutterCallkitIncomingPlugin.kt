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
import com.getcapacitor.JSObject
import com.getcapacitor.Logger
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin
import com.hiennv.flutter_callkit_incoming.Utils.Companion.reapCollection
import org.json.JSONObject
import java.lang.ref.WeakReference

import android.Manifest
import android.app.Notification
import android.app.NotificationManager
import android.content.pm.PackageManager
import android.os.Bundle
import androidx.appcompat.app.AppCompatActivity
import com.getcapacitor.Bridge
import com.getcapacitor.annotation.Permission
import com.getcapacitor.PermissionState
import com.getcapacitor.annotation.PermissionCallback
import com.google.android.gms.tasks.Task
import com.google.firebase.messaging.CommonNotificationBuilder
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.NotificationParams
import com.google.firebase.messaging.RemoteMessage
import org.json.JSONException
import java.util.Arrays

/** FlutterCallkitIncomingPlugin */
@CapacitorPlugin(
    name = "FlutterCallkitIncoming",
    permissions = [
        Permission(
            strings = [Manifest.permission.POST_NOTIFICATIONS],
            alias = FlutterCallkitIncomingPlugin.PUSH_NOTIFICATIONS
        )
    ]
)
class FlutterCallkitIncomingPlugin : Plugin() {
    companion object {

        const val EXTRA_CALLKIT_CALL_DATA = "EXTRA_CALLKIT_CALL_DATA"

        @SuppressLint("StaticFieldLeak")
        private lateinit var instance: FlutterCallkitIncomingPlugin

        const val PUSH_NOTIFICATIONS: String = "receive"

        var staticBridge: Bridge? = null
        var lastMessage: RemoteMessage? = null
        var lastAcceptCallEvent: Map<String, Map<String, Any>>? = null
        var lastIncomingCallEvent: Map<String, Map<String, Any>>? = null
        private const val EVENT_TOKEN_CHANGE = "registration"
        private const val EVENT_TOKEN_ERROR = "registrationError"

        fun onNewToken(newToken: String?) {
            val pushPlugin =
                pushNotificationsInstance
            pushPlugin?.sendToken(newToken)
        }

        fun sendRemoteMessage(remoteMessage: RemoteMessage, fcmContext: Context) {
            val callOptions: String? = remoteMessage.data["call"]
            val deleteCallOptions: String? = remoteMessage.data["deleteCall"]
            val pushPlugin =
                pushNotificationsInstance
            if (pushPlugin != null) {
                pushPlugin.fireNotification(remoteMessage)
            } else {
                lastMessage = remoteMessage
            }
            if (callOptions != null || deleteCallOptions != null) {
                val activeInstance = pushPlugin ?: FlutterCallkitIncomingPlugin()
                if (pushPlugin == null) {
                    initSharedInstance(fcmContext, activeInstance)
                }
                if (deleteCallOptions != null) activeInstance.endCall(Data(jsonParser(deleteCallOptions)))
                if (callOptions != null) activeInstance.showIncomingNotification(Data(jsonParser(callOptions)))
            }
        }

        val pushNotificationsInstance: FlutterCallkitIncomingPlugin?
            get() {
                if (staticBridge != null && staticBridge!!.webView != null) {
                    val handle =
                        staticBridge!!.getPlugin("FlutterCallkitIncoming")
                            ?: return null
                    return handle.instance as FlutterCallkitIncomingPlugin
                }
                return null
            }

        public fun getInstance(): FlutterCallkitIncomingPlugin {
            return instance
        }

        public fun hasInstance(): Boolean {
            return ::instance.isInitialized
        }

        fun initSharedInstance(context: Context, pluginInstance: FlutterCallkitIncomingPlugin) {
            instance = pushNotificationsInstance ?: pluginInstance
            instance.callkitNotificationManager = CallkitNotificationManager(context)
            instance.context = context
        }

        fun sendEvent(event: String, mapBody: Map<String, Any>) {
            val body = JSObject()
            for ((key, value) in mapBody) {
                body.put(key, value)
            }
            val pushPlugin =
                pushNotificationsInstance
            if (pushPlugin != null) {
                pushPlugin.notifyListeners(event, body)
            } else {
                if (event == CallkitConstants.ACTION_CALL_ACCEPT) lastAcceptCallEvent = buildMap { put(event, mapBody) }
                else if (event == CallkitConstants.ACTION_CALL_INCOMING) lastIncomingCallEvent = buildMap { put(event, mapBody) }
            }
        }

        public fun sendEventCustom(event: String, mapBody: Map<String, Any>) {
            val body = JSObject()
            for ((key, value) in mapBody) {
                body.put(key, value)
            }
            this.getInstance().notifyListeners(event, body)
        }

        public fun jsonParser(jsonString: String): MutableMap<String, Any?> {
            val defaultMap: MutableMap<String, Any?> = mutableMapOf()
            try {
                val parser: Parser = Parser.default()
                val ojsJsonObject = parser.parse(StringBuilder(jsonString)) as JsonObject
                val options = ojsJsonObject.toMutableMap()
                for ((key, value) in options) {
                    if (value is JsonObject) {
                        options[key] = value.toMutableMap()
                    }
                }
                return options
            } catch (e: PackageManager.NameNotFoundException) {
                e.printStackTrace()
            }
            return defaultMap
        }

    }
    var notificationManager: NotificationManager? = null
    var firebaseMessagingService: MessagingService? = null
    private var notificationChannelManager: NotificationChannelManager? = null

    /// The MethodChannel that will the communication between Flutter and native Android
    ///
    /// This local reference serves to register the plugin with the Flutter Engine and unregister it
    /// when the Flutter Engine is detached from the Activity
    private var activity: Activity? = null
    private var context: Context? = null
    private var callkitNotificationManager: CallkitNotificationManager? = null

    override fun load() {
        activity = getActivity()
        context = getActivity()?.applicationContext
        notificationManager =
            activity?.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        firebaseMessagingService = MessagingService()

        staticBridge = this.bridge
        initSharedInstance(context as Context, this)
        if (lastMessage != null) {
            fireNotification(lastMessage!!)
            lastMessage = null
        }

        notificationChannelManager = NotificationChannelManager(
            activity as AppCompatActivity,
            notificationManager!!, config
        )
    }

    override fun handleOnNewIntent(data: Intent) {
        super.handleOnNewIntent(data)
        val bundle = data.extras
        if (bundle != null && bundle.containsKey("google.message_id")) {
            val notificationJson = JSObject()
            val dataObject = JSObject()
            for (key in bundle.keySet()) {
                if (key == "google.message_id") {
                    notificationJson.put("id", bundle.getString(key))
                } else {
                    val valueStr = bundle.getString(key)
                    dataObject.put(key, valueStr)
                }
            }
            notificationJson.put("data", dataObject)
            val actionJson = JSObject()
            actionJson.put("actionId", "tap")
            actionJson.put("notification", notificationJson)
            notifyListeners("pushNotificationActionPerformed", actionJson, true)
        }
    }

    @PluginMethod
    override fun checkPermissions(call: PluginCall) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            val permissionsResultJSON = JSObject()
            permissionsResultJSON.put("receive", "granted")
            call.resolve(permissionsResultJSON)
        } else {
            super.checkPermissions(call)
        }
    }

    @PluginMethod
    override fun requestPermissions(call: PluginCall) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU || getPermissionState(
                PUSH_NOTIFICATIONS
            ) == PermissionState.GRANTED
        ) {
            val permissionsResultJSON = JSObject()
            permissionsResultJSON.put("receive", "granted")
            call.resolve(permissionsResultJSON)
        } else {
            requestPermissionForAlias(PUSH_NOTIFICATIONS, call, "permissionsCallback")
        }
    }

    @PluginMethod
    fun register(call: PluginCall) {
        FirebaseMessaging.getInstance().isAutoInitEnabled = true
        FirebaseMessaging
            .getInstance()
            .token
            .addOnCompleteListener { task: Task<String?> ->
                if (!task.isSuccessful) {
                    sendError(task.exception!!.localizedMessage)
                    return@addOnCompleteListener
                }
                sendToken(task.result)
            }
        call.resolve()
    }

    @PluginMethod
    fun unregister(call: PluginCall) {
        FirebaseMessaging.getInstance().isAutoInitEnabled = false
        FirebaseMessaging.getInstance().deleteToken()
        call.resolve()
    }

    @PluginMethod
    fun getDeliveredNotifications(call: PluginCall) {
        val notifications = JSArray()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val activeNotifications = notificationManager!!.activeNotifications

            for (notif in activeNotifications) {
                val jsNotif = JSObject()

                jsNotif.put("id", notif.id)
                jsNotif.put("tag", notif.tag)

                val notification = notif.notification
                if (notification != null) {
                    jsNotif.put(
                        "title",
                        notification.extras.getCharSequence(Notification.EXTRA_TITLE)
                    )
                    jsNotif.put(
                        "body",
                        notification.extras.getCharSequence(Notification.EXTRA_TEXT)
                    )
                    jsNotif.put("group", notification.group)
                    jsNotif.put(
                        "groupSummary",
                        0 != (notification.flags and Notification.FLAG_GROUP_SUMMARY)
                    )

                    val extras = JSObject()

                    for (key in notification.extras.keySet()) {
                        extras.put(key, notification.extras.getString(key))
                    }

                    jsNotif.put("data", extras)
                }

                notifications.put(jsNotif)
            }
        }

        val result = JSObject()
        result.put("notifications", notifications)
        call.resolve(result)
    }

    @PluginMethod
    fun removeDeliveredNotifications(call: PluginCall) {
        val notifications = call.getArray("notifications")

        try {
            for (o in notifications.toList<Any>()) {
                if (o is JSONObject) {
                    val notif = JSObject.fromJSONObject(o)
                    val tag = notif.getString("tag")
                    val id = notif.getInteger("id")

                    if (tag == null) {
                        notificationManager!!.cancel(id!!)
                    } else {
                        notificationManager!!.cancel(tag, id!!)
                    }
                } else {
                    call.reject("Expected notifications to be a list of notification objects")
                }
            }
        } catch (e: JSONException) {
            call.reject(e.message)
        }

        call.resolve()
    }

    @PluginMethod
    fun removeAllDeliveredNotifications(call: PluginCall) {
        notificationManager!!.cancelAll()
        call.resolve()
    }

    @PluginMethod
    fun createChannel(call: PluginCall) {
        notificationChannelManager!!.createChannel(call)
    }

    @PluginMethod
    fun deleteChannel(call: PluginCall) {
        notificationChannelManager!!.deleteChannel(call)
    }

    @PluginMethod
    fun listChannels(call: PluginCall) {
        notificationChannelManager!!.listChannels(call)
    }

    fun sendToken(token: String?) {
        val data = JSObject()
        data.put("value", token)
        notifyListeners(EVENT_TOKEN_CHANGE, data, true)
    }

    fun sendError(error: String?) {
        val data = JSObject()
        data.put("error", error)
        notifyListeners(EVENT_TOKEN_ERROR, data, true)
    }

    fun fireNotification(remoteMessage: RemoteMessage) {
        val remoteMessageData = JSObject()

        val data = JSObject()
        remoteMessageData.put("id", remoteMessage.messageId)
        for (key in remoteMessage.data.keys) {
            val value: Any? = remoteMessage.data[key]
            data.put(key, value)
        }
        remoteMessageData.put("data", data)

        val notification = remoteMessage.notification
        if (notification != null) {
            val title = notification.title
            val body = notification.body
            val presentation = config.getArray("presentationOptions")
            if (presentation != null) {
                if (Arrays.asList(*presentation).contains("alert")) {
                    var bundle: Bundle? = null
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        try {
                            val applicationInfo = context?.let {
                                context!!
                                    .packageManager
                                    .getApplicationInfo(
                                        it.packageName,
                                        PackageManager.ApplicationInfoFlags.of(PackageManager.GET_META_DATA.toLong())
                                    )
                            }
                            if (applicationInfo != null) {
                                bundle = applicationInfo.metaData
                            }
                        } catch (e: PackageManager.NameNotFoundException) {
                            e.printStackTrace()
                        }
                    } else {
                        bundle = bundleLegacy
                    }

                    if (bundle != null) {
                        val params = NotificationParams(remoteMessage.toIntent().extras!!)

                        val channelId = CommonNotificationBuilder.getOrCreateChannel(
                            context,
                            params.notificationChannelId,
                            bundle
                        )

                        val notificationInfo = CommonNotificationBuilder.createNotificationInfo(
                            context,
                            context,
                            params,
                            channelId,
                            bundle
                        )

                        notificationManager!!.notify(
                            notificationInfo.tag,
                            notificationInfo.id,
                            notificationInfo.notificationBuilder.build()
                        )
                    }
                }
            }
            remoteMessageData.put("title", title)
            remoteMessageData.put("body", body)
            remoteMessageData.put("click_action", notification.clickAction)

            val link = notification.link
            if (link != null) {
                remoteMessageData.put("link", link.toString())
            }
        }

        notifyListeners("pushNotificationReceived", remoteMessageData, true)
    }

    @PermissionCallback
    private fun permissionsCallback(call: PluginCall) {
        this.checkPermissions(call)
    }

    @get:Suppress("deprecation")
    private val bundleLegacy: Bundle?
        get() {
            try {
                val applicationInfo = context?.let {
                    context!!
                        .packageManager
                        .getApplicationInfo(
                            it.packageName,
                            PackageManager.GET_META_DATA
                        )
                }
                if (applicationInfo != null) {
                    return applicationInfo.metaData
                }
            } catch (e: PackageManager.NameNotFoundException) {
                e.printStackTrace()
                return null
            }
            return null
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

    private fun sendPendingAcceptEvent() {
        if (lastIncomingCallEvent != null) {
            for ((key, value) in lastIncomingCallEvent!!) {
                sendEvent(key, value)
            }
            lastIncomingCallEvent = null
        }
        if (lastAcceptCallEvent != null) {
            for ((key, value) in lastAcceptCallEvent!!) {
                sendEvent(key, value)
            }
            lastAcceptCallEvent = null
        }
    }

    @PluginMethod
    public fun onMethod(call: PluginCall) {
        try {
            val name: String = call.getString("methodName")!!
            val ojsString: String = call.getString("options")!!
            val options = jsonParser(ojsString)
            when (name) {
                "sendPendingAcceptEvent" -> {
                    sendPendingAcceptEvent()
                    call.resolve()
                }

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
