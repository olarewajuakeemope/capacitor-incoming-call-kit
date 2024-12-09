import type { PluginListenerHandle } from '@capacitor/core'

export type MethodNames =  |
  'showCallkitIncoming' |
  'showCallkitIncomingSilently' |
  'showMissCallNotification' |
  'startCall' |
  'muteCall' |
  'holdCall' |
  'isMuted' |
  'endCall' |
  'callConnected' |
  'endAllCalls' |
  'activeCalls' |
  'getDevicePushTokenVoIP' |
  'silenceEvents' |
  'requestNotificationPermission' |
  'requestFullIntentPermission' |
  'hideCallkitIncoming' |
  'endNativeSubsystemOnly' |
  'setAudioRoute'

export type Events = |
  'com.hiennv.flutter_callkit_incoming.DID_UPDATE_DEVICE_PUSH_TOKEN_VOIP' |
  'com.hiennv.flutter_callkit_incoming.ACTION_CALL_INCOMING' |
  'com.hiennv.flutter_callkit_incoming.ACTION_CALL_START' |
  'com.hiennv.flutter_callkit_incoming.ACTION_CALL_ACCEPT' |
  'com.hiennv.flutter_callkit_incoming.ACTION_CALL_DECLINE' |
  'com.hiennv.flutter_callkit_incoming.ACTION_CALL_ENDED' |
  'com.hiennv.flutter_callkit_incoming.ACTION_CALL_TIMEOUT' |
  'com.hiennv.flutter_callkit_incoming.ACTION_CALL_CALLBACK' |
  'com.hiennv.flutter_callkit_incoming.ACTION_CALL_TOGGLE_HOLD' |
  'com.hiennv.flutter_callkit_incoming.ACTION_CALL_TOGGLE_MUTE' |
  'com.hiennv.flutter_callkit_incoming.ACTION_CALL_TOGGLE_DMTF' |
  'com.hiennv.flutter_callkit_incoming.ACTION_CALL_TOGGLE_GROUP' |
  'com.hiennv.flutter_callkit_incoming.ACTION_CALL_TOGGLE_AUDIO_SESSION' |
  'com.hiennv.flutter_callkit_incoming.ACTION_CALL_CUSTOM'

// export enum Events {
//   actionDidUpdateDevicePushTokenVoip = 'com.hiennv.flutter_callkit_incoming.DID_UPDATE_DEVICE_PUSH_TOKEN_VOIP',
//   actionCallIncoming = 'com.hiennv.flutter_callkit_incoming.ACTION_CALL_INCOMING',
//   actionCallStart = 'com.hiennv.flutter_callkit_incoming.ACTION_CALL_START',
//   actionCallAccept = 'com.hiennv.flutter_callkit_incoming.ACTION_CALL_ACCEPT',
//   actionCallDecline = 'com.hiennv.flutter_callkit_incoming.ACTION_CALL_DECLINE',
//   actionCallEnded = 'com.hiennv.flutter_callkit_incoming.ACTION_CALL_ENDED',
//   actionCallTimeout = 'com.hiennv.flutter_callkit_incoming.ACTION_CALL_TIMEOUT',
//   actionCallCallback = 'com.hiennv.flutter_callkit_incoming.ACTION_CALL_CALLBACK',
//   actionCallToggleHold = 'com.hiennv.flutter_callkit_incoming.ACTION_CALL_TOGGLE_HOLD',
//   actionCallToggleMute = 'com.hiennv.flutter_callkit_incoming.ACTION_CALL_TOGGLE_MUTE',
//   actionCallToggleDmtf = 'com.hiennv.flutter_callkit_incoming.ACTION_CALL_TOGGLE_DMTF',
//   actionCallToggleGroup = 'com.hiennv.flutter_callkit_incoming.ACTION_CALL_TOGGLE_GROUP',
//   actionCallToggleAudioSession = 'com.hiennv.flutter_callkit_incoming.ACTION_CALL_TOGGLE_AUDIO_SESSION',
//   actionCallCustom = 'com.hiennv.flutter_callkit_incoming.ACTION_CALL_CUSTOM',
// }

export interface NotificationParams {
  id?: number
  showNotification?: boolean
  subtitle?: string
  callbackText?: string
  isShowCallback: boolean
  int?: number
}

export interface IOSParams {
  /// App's Icon. using for display inside Callkit(iOS)
  iconName?: string

  /// Type handle call `generic`, `number`, `email`
  handleType?: string
  supportsVideo?: boolean
  maximumCallGroups?: number
  maximumCallsPerCallGroup?: number
  audioSessionMode?: string
  audioSessionActive?: boolean
  audioSessionPreferredSampleRate?: number // Float value
  audioSessionPreferredIOBufferDuration?: number // Float value
  configureAudioSession?: boolean
  supportsDTMF?: boolean
  supportsHolding?: boolean
  supportsGrouping?: boolean
  supportsUngrouping?: boolean

  /// Add file to root project xcode /ios/Runner/Ringtone.caf and Copy Bundle Resources(Build Phases) -> value: "Ringtone.caf"
  ringtonePath?: string
}

export interface AndroidParams {
  /// Using custom notifications.
  isCustomNotification?: boolean

  /// Using custom notification small on some devices clipped out in android.
  isCustomSmallExNotification?: boolean

  /// Show logo app inside full screen.
  isShowLogo?: boolean

  /// Show call id app inside full screen.
  isShowCallID?: boolean

  /// File name ringtone, put file into /android/app/src/main/res/raw/ringtone_default.pm3 -> value: `ringtone_default.pm3`
  ringtonePath?: string

  /// Incoming call screen background color.
  backgroundColor?: string

  /// Using image background for Incoming call screen. example: http://... https://... or "assets/abc.png"
  backgroundUrl?: string

  /// Color used in button/text on notification.
  actionColor?: string

  /// Color used for the text in the full screen notification
  textColor?: string

  /// Notification channel name of incoming call.
  incomingCallNotificationChannelName?: string

  /// Notification channel name of missed call.
  missedCallNotificationChannelName?: string

  /// Show full locked screen.
  isShowFullLockedScreen?: boolean

  /// Caller is important to the user of this device with regards to how frequently they interact.
  /// https://developer.android.com/reference/androidx/core/app/Person#isImportant()
  isImportant?: boolean

  /// Used primarily to identify automated tooling.
  /// https://developer.android.com/reference/androidx/core/app/Person#isBot()
  isBot?: boolean
}

export interface CallKitParams {
  id?: string
  nameCaller?: string
  appName?: string
  avatar?: string
  handle?: string
  type?: number
  normalHandle?: number
  duration?: number
  textAccept?: string
  textDecline?: string
  textMissedCall?: string
  textCallback?: string
  rationaleMessagePermission?: string
  postNotificationMessageRequired?: string
  missedCallNotification?: NotificationParams
  extra?: {[key:string]: any}
  headers?: {[key:string]: any}
  android?: AndroidParams
  ios?: IOSParams,
}

export type Responses = void | { isMuted: boolean } | { calls: CallKitParams[] } | { devicePushTokenVoIP: string }

export interface FlutterCallkitIncomingPlugin {
  onMethod(options: {
    options: string
    methodName: MethodNames
    parsedOptions: CallKitParams
  }): Promise<Responses>
  addListener: (even: Events, cb: (data: any) => void) => Promise<PluginListenerHandle>
}
