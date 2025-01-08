package com.hiennv.flutter_callkit_incoming

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.ContentResolver
import android.content.Context
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import androidx.core.app.NotificationCompat
import com.getcapacitor.JSArray
import com.getcapacitor.JSObject
import com.getcapacitor.Logger
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginConfig
import com.getcapacitor.util.WebColor

class NotificationChannelManager(
    private val context: Context,
    private val notificationManager: NotificationManager,
    private val config: PluginConfig
) {
    fun createChannel(call: PluginCall) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = JSObject()
            if (call.getString(CHANNEL_ID) != null) {
                channel.put(CHANNEL_ID, call.getString(CHANNEL_ID))
            } else {
                call.reject("Channel missing identifier")
                return
            }
            if (call.getString(CHANNEL_NAME) != null) {
                channel.put(CHANNEL_NAME, call.getString(CHANNEL_NAME))
            } else {
                call.reject("Channel missing name")
                return
            }

            channel.put(
                CHANNEL_IMPORTANCE,
                call.getInt(CHANNEL_IMPORTANCE, NotificationManager.IMPORTANCE_DEFAULT)
            )
            channel.put(CHANNEL_DESCRIPTION, call.getString(CHANNEL_DESCRIPTION, ""))
            channel.put(
                CHANNEL_VISIBILITY,
                call.getInt(CHANNEL_VISIBILITY, NotificationCompat.VISIBILITY_PUBLIC)
            )
            channel.put(CHANNEL_SOUND, call.getString(CHANNEL_SOUND, null))
            channel.put(CHANNEL_VIBRATE, call.getBoolean(CHANNEL_VIBRATE, false))
            channel.put(CHANNEL_USE_LIGHTS, call.getBoolean(CHANNEL_USE_LIGHTS, false))
            channel.put(CHANNEL_LIGHT_COLOR, call.getString(CHANNEL_LIGHT_COLOR, null))
            createChannel(channel)
            call.resolve()
        } else {
            call.unavailable()
        }
    }

    fun createChannel(channel: JSObject) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationChannel = NotificationChannel(
                channel.getString(CHANNEL_ID),
                channel.getString(CHANNEL_NAME),
                channel.getInteger(CHANNEL_IMPORTANCE)!!
            )
            notificationChannel.description =
                channel.getString(CHANNEL_DESCRIPTION)
            notificationChannel.lockscreenVisibility = channel.getInteger(CHANNEL_VISIBILITY)!!
            notificationChannel.enableVibration(channel.getBool(CHANNEL_VIBRATE)!!)
            notificationChannel.enableLights(channel.getBool(CHANNEL_USE_LIGHTS)!!)
            val lightColor = channel.getString(CHANNEL_LIGHT_COLOR)
            if (lightColor != null) {
                try {
                    notificationChannel.lightColor = WebColor.parseColor(lightColor)
                } catch (ex: IllegalArgumentException) {
                    Logger.error(
                        Logger.tags("NotificationChannel"),
                        "Invalid color provided for light color.",
                        null
                    )
                }
            }
            var sound = channel.getString(CHANNEL_SOUND, null)
            if (sound != null && !sound.isEmpty()) {
                if (sound.contains(".")) {
                    sound = sound.substring(0, sound.lastIndexOf('.'))
                }
                val audioAttributes = AudioAttributes.Builder()
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .build()
                val soundUri =
                    Uri.parse(ContentResolver.SCHEME_ANDROID_RESOURCE + "://" + context.packageName + "/raw/" + sound)
                notificationChannel.setSound(soundUri, audioAttributes)
            }
            notificationManager.createNotificationChannel(notificationChannel)
        }
    }

    fun deleteChannel(call: PluginCall) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channelId = call.getString("id")
            notificationManager.deleteNotificationChannel(channelId)
            call.resolve()
        } else {
            call.unavailable()
        }
    }

    fun listChannels(call: PluginCall) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val notificationChannels = notificationManager.notificationChannels
            val channels = JSArray()
            for (notificationChannel in notificationChannels) {
                val channel = JSObject()
                channel.put(CHANNEL_ID, notificationChannel.id)
                channel.put(CHANNEL_NAME, notificationChannel.name)
                channel.put(CHANNEL_DESCRIPTION, notificationChannel.description)
                channel.put(CHANNEL_IMPORTANCE, notificationChannel.importance)
                channel.put(CHANNEL_VISIBILITY, notificationChannel.lockscreenVisibility)
                channel.put(CHANNEL_SOUND, notificationChannel.sound)
                channel.put(CHANNEL_VIBRATE, notificationChannel.shouldVibrate())
                channel.put(CHANNEL_USE_LIGHTS, notificationChannel.shouldShowLights())
                channel.put(
                    CHANNEL_LIGHT_COLOR,
                    String.format("#%06X", (0xFFFFFF and notificationChannel.lightColor))
                )
                Logger.debug(
                    Logger.tags("NotificationChannel"),
                    "visibility " + notificationChannel.lockscreenVisibility
                )
                Logger.debug(
                    Logger.tags("NotificationChannel"),
                    "importance " + notificationChannel.importance
                )
                channels.put(channel)
            }
            val result = JSObject()
            result.put("channels", channels)
            call.resolve(result)
        } else {
            call.unavailable()
        }
    }

    companion object {
        private const val CHANNEL_ID = "id"
        private const val CHANNEL_NAME = "name"
        private const val CHANNEL_DESCRIPTION = "description"
        private const val CHANNEL_IMPORTANCE = "importance"
        private const val CHANNEL_VISIBILITY = "visibility"
        private const val CHANNEL_SOUND = "sound"
        private const val CHANNEL_VIBRATE = "vibration"
        private const val CHANNEL_USE_LIGHTS = "lights"
        private const val CHANNEL_LIGHT_COLOR = "lightColor"
    }
}
