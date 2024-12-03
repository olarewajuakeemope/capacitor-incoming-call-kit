package com.hiennv.flutter_callkit_incoming;

import android.util.Log;

public class FlutterCallkitIncomingPlugin {

    public String echo(String value) {
        Log.i("Echo", value);
        return value;
    }
}
