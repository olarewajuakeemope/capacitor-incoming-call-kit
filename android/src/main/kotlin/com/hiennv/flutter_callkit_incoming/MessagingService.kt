package com.hiennv.flutter_callkit_incoming

import android.util.Log
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class MessagingService : FirebaseMessagingService() {
    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        super.onMessageReceived(remoteMessage)
        FlutterCallkitIncomingPlugin.sendRemoteMessage(remoteMessage, applicationContext)
    }

    override fun onNewToken(s: String) {
        super.onNewToken(s)
        FlutterCallkitIncomingPlugin.onNewToken(s)
    }
}
