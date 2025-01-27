import UIKit
import CallKit
import Capacitor
import AVFoundation

import Foundation
import UserNotifications

enum PushNotificationError: Error {
    case tokenParsingFailed
    case tokenRegistrationFailed
}

enum PushNotificationsPermissions: String {
    case prompt
    case denied
    case granted
}

@available(iOS 10.0, *)
@objc(SwiftFlutterCallkitIncomingPlugin)
public class SwiftFlutterCallkitIncomingPlugin: CAPPlugin, CAPBridgedPlugin, CXProviderDelegate {
    public let identifier = "SwiftFlutterCallkitIncomingPlugin"
    public let jsName = "FlutterCallkitIncoming"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "onMethod", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "register", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "unregister", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "checkPermissions", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "requestPermissions", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getDeliveredNotifications", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "removeAllDeliveredNotifications", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "removeDeliveredNotifications", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "createChannel", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "listChannels", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "deleteChannel", returnType: CAPPluginReturnPromise)
    ]
    private let notificationDelegateHandler = PushNotificationsHandler()
    private var appDelegateRegistrationCalled: Bool = false
    
    static let ACTION_DID_UPDATE_DEVICE_PUSH_TOKEN_VOIP = "com.hiennv.flutter_callkit_incoming.DID_UPDATE_DEVICE_PUSH_TOKEN_VOIP"
    
    static let ACTION_CALL_INCOMING = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_INCOMING"
    public static let ACTION_CALL_START = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_START"
    public static let ACTION_CALL_ACCEPT = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_ACCEPT"
    static let ACTION_CALL_DECLINE = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_DECLINE"
    static let ACTION_CALL_ENDED = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_ENDED"
    public static let ACTION_CALL_TIMEOUT = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_TIMEOUT"
    static let ACTION_CALL_CUSTOM = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_CUSTOM"
    
    static let ACTION_CALL_TOGGLE_HOLD = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_TOGGLE_HOLD"
    static let ACTION_CALL_TOGGLE_MUTE = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_TOGGLE_MUTE"
    static let ACTION_CALL_TOGGLE_DMTF = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_TOGGLE_DMTF"
    static let ACTION_CALL_TOGGLE_GROUP = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_TOGGLE_GROUP"
    static let ACTION_CALL_TOGGLE_AUDIO_SESSION = "com.hiennv.flutter_callkit_incoming.ACTION_CALL_TOGGLE_AUDIO_SESSION"
    
    @objc public private(set) static var sharedInstance: SwiftFlutterCallkitIncomingPlugin!
    
    private var callManager: CallManager
    
    private var sharedProvider: CXProvider? = nil
    
    private var outgoingCall : Call?
    private var answerCall : Call?
    
    private var data: Data?
    private var isFromPushKit: Bool = false
    private var silenceEvents: Bool = false
    private var lastAcceptCallEvent: [String : Any]?
    private var lastIncomingCallEvent: [String : Any]?
    private let devicePushTokenVoIP = "DevicePushTokenVoIP"
    private func postRequest(_ url: String, _ json: String?) {
        if (self.bridge == nil) {
            Task {
                do {
    //                NSLog("postRequest with url: \(String(describing: url)) and json: \(String(describing: json))")
                    var request = URLRequest(url: URL(string: url)!)
                    request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

                    // Use the async variant of URLSession to make an HTTP POST request:
                    request.httpMethod = "POST"
                    let (_, _) = try await URLSession.shared.upload(for: request, from: json?.data(using: .utf8) ?? Foundation.Data())
    //                NSLog("postRequest successful with response: \(String(describing: response)) and data: \(String(decoding: data, as: UTF8.self))")
                } catch {
                    NSLog("postRequest attempt with error \(String(describing: error))")
                }
            }
        } else {
            NSLog("postRequest ignored for \(String(describing: url)) as app is active")
        }
    }
    
    public func sendEvent(_ event: String, _ body: [String : Any]?) {
        if silenceEvents {
            print(event, " silenced")
            return
        } else {
            if (self.bridge != nil) {
                self.notifyListeners(event, data: body ?? [:])
            } else {
                if (event == SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_ACCEPT) {
                    lastAcceptCallEvent = body
                } else if (event == SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_INCOMING) {
                    lastIncomingCallEvent = body
                }
            }
        }
        
    }
    
    @objc public func sendEventCustom(_ event: String, body: [String : Any]?) {
        self.notifyListeners(event, data: body ?? [:])
    }
    
    public static func sharePluginWithRegister(with pluginInstance: SwiftFlutterCallkitIncomingPlugin) {
        if(sharedInstance == nil){
            sharedInstance = pluginInstance
        }
    }
    
    override public func load() {
        SwiftFlutterCallkitIncomingPlugin.sharePluginWithRegister(with: self)

        self.bridge?.notificationRouter.pushNotificationHandler = self.notificationDelegateHandler
        self.notificationDelegateHandler.plugin = self

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.didRegisterForRemoteNotificationsWithDeviceToken(notification:)),
                                               name: .capacitorDidRegisterForRemoteNotifications,
                                               object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.didFailToRegisterForRemoteNotificationsWithError(notification:)),
                                               name: .capacitorDidFailToRegisterForRemoteNotifications,
                                               object: nil)
    }
    
    public override init() {
        callManager = CallManager()
        super.init()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /**
     * Register for push notifications
     */
    @objc func register(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
        call.resolve()
    }

    /**
     * Unregister for remote notifications
     */
    @objc func unregister(_ call: CAPPluginCall) {
        DispatchQueue.main.async {
            UIApplication.shared.unregisterForRemoteNotifications()
            call.resolve()
        }
    }

    /**
     * Request notification permission
     */
    @objc override public func requestPermissions(_ call: CAPPluginCall) {
        self.notificationDelegateHandler.requestPermissions { granted, error in
            guard error == nil else {
                if let err = error {
                    call.reject(err.localizedDescription)
                    return
                }

                call.reject("unknown error in permissions request")
                return
            }

            var result: PushNotificationsPermissions = .denied

            if granted {
                result = .granted
            }

            call.resolve(["receive": result.rawValue])
        }
    }

    /**
     * Check notification permission
     */
    @objc override public func checkPermissions(_ call: CAPPluginCall) {
        self.notificationDelegateHandler.checkPermissions { status in
            var result: PushNotificationsPermissions = .prompt

            switch status {
            case .notDetermined:
                result = .prompt
            case .denied:
                result = .denied
            case .ephemeral, .authorized, .provisional:
                result = .granted
            @unknown default:
                result = .prompt
            }

            call.resolve(["receive": result.rawValue])
        }
    }

    /**
     * Get notifications in Notification Center
     */
    @objc func getDeliveredNotifications(_ call: CAPPluginCall) {
        if !appDelegateRegistrationCalled {
            call.reject("event capacitorDidRegisterForRemoteNotifications not called.  Visit https://capacitorjs.com/docs/apis/push-notifications for more information")
            return
        }
        UNUserNotificationCenter.current().getDeliveredNotifications(completionHandler: { (notifications) in
            let ret = notifications.map({ (notification) -> [String: Any] in
                return self.notificationDelegateHandler.makeNotificationRequestJSObject(notification.request)
            })
            call.resolve([
                "notifications": ret
            ])
        })
    }

    /**
     * Remove specified notifications from Notification Center
     */
    @objc func removeDeliveredNotifications(_ call: CAPPluginCall) {
        if !appDelegateRegistrationCalled {
            call.reject("event capacitorDidRegisterForRemoteNotifications not called.  Visit https://capacitorjs.com/docs/apis/push-notifications for more information")
            return
        }
        guard let notifications = call.getArray("notifications", JSObject.self) else {
            call.reject("Must supply notifications to remove")
            return
        }

        let ids = notifications.map { $0["id"] as? String ?? "" }
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
        call.resolve()
    }

    /**
     * Remove all notifications from Notification Center
     */
    @objc func removeAllDeliveredNotifications(_ call: CAPPluginCall) {
        if !appDelegateRegistrationCalled {
            call.reject("event capacitorDidRegisterForRemoteNotifications not called.  Visit https://capacitorjs.com/docs/apis/push-notifications for more information")
            return
        }
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
        DispatchQueue.main.async(execute: {
            UIApplication.shared.applicationIconBadgeNumber = 0
        })
        call.resolve()
    }

    @objc func createChannel(_ call: CAPPluginCall) {
        call.unimplemented("Not available on iOS")
    }

    @objc func deleteChannel(_ call: CAPPluginCall) {
        call.unimplemented("Not available on iOS")
    }

    @objc func listChannels(_ call: CAPPluginCall) {
        call.unimplemented("Not available on iOS")
    }

    @objc public func didRegisterForRemoteNotificationsWithDeviceToken(notification: NSNotification) {
        appDelegateRegistrationCalled = true
        if let deviceToken = notification.object as? Foundation.Data {
            let deviceTokenString = deviceToken.reduce("", {$0 + String(format: "%02X", $1)})
            notifyListeners("registration", data: [
                "value": deviceTokenString
            ])
        } else if let stringToken = notification.object as? String {
            notifyListeners("registration", data: [
                "value": stringToken
            ])
        } else {
            notifyListeners("registrationError", data: [
                "error": PushNotificationError.tokenParsingFailed.localizedDescription
            ])
        }
    }

    @objc public func didFailToRegisterForRemoteNotificationsWithError(notification: NSNotification) {
        appDelegateRegistrationCalled = true
        guard let error = notification.object as? Error else {
            return
        }
        notifyListeners("registrationError", data: [
            "error": error.localizedDescription
        ])
    }
    
    @objc public func onMethod(_ pluginCall: CAPPluginCall) {
        let name = pluginCall.getString("methodName") ?? ""
        let options = pluginCall.getObject("parsedOptions")
        switch name {
        case "checkIsVersionOk":
            checkIsVersionOk(pluginCall)
            break
        case "sendPendingAcceptEvent":
            sendPendingAcceptEvent()
            pluginCall.resolve()
            break
        case "showCallkitIncoming":
            guard let getArgs = options else {
                pluginCall.resolve()
                return
            }
            self.data = Data(args: getArgs)
            showCallkitIncoming(self.data!, fromPushKit: false)
            pluginCall.resolve()
            break
        case "showMissCallNotification":
            pluginCall.resolve()
            break
        case "startCall":
            guard let args = options else {
                pluginCall.resolve()
                return
            }
            if let getArgs = options {
                self.data = Data(args: getArgs)
                self.startCall(self.data!, fromPushKit: false)
            }
            pluginCall.resolve()
            break
        case "endCall":
            guard let args = options else {
                pluginCall.resolve()
                return
            }
            if(self.isFromPushKit){
                self.endCall(self.data!)
            }else{
                if let getArgs = options {
                    self.data = Data(args: getArgs)
                    self.endCall(self.data!)
                }
            }
            pluginCall.resolve()
            break
        case "muteCall":
            guard let args = options,
                  let callId = args["id"] as? String,
                  let isMuted = args["isMuted"] as? Bool else {
                pluginCall.resolve()
                return
            }
            
            self.muteCall(callId, isMuted: isMuted)
            pluginCall.resolve()
            break
        case "isMuted":
            guard let args = options,
                  let callId = args["id"] as? String else{
                pluginCall.resolve(["isMuted": false])
                return
            }
            guard let callUUID = UUID(uuidString: callId),
                  let call = self.callManager.callWithUUID(uuid: callUUID) else {
                pluginCall.resolve(["isMuted": false])
                return
            }
            pluginCall.resolve(["isMuted": call.isMuted])
            break
        case "holdCall":
            guard let args = options as? [String: Any] ,
                  let callId = args["id"] as? String,
                  let onHold = args["isOnHold"] as? Bool else {
                pluginCall.resolve()
                return
            }
            self.holdCall(callId, onHold: onHold)
            pluginCall.resolve()
            break
        case "callConnected":
            guard let args = options else {
                pluginCall.resolve()
                return
            }
            if(self.isFromPushKit){
                self.connectedCall(self.data!)
            }else{
                if let getArgs = options {
                    self.data = Data(args: getArgs)
                    self.connectedCall(self.data!)
                }
            }
            pluginCall.resolve()
            break
        case "activeCalls":
            pluginCall.resolve(["calls": self.callManager.activeCalls()])
            break;
        case "endAllCalls":
            self.callManager.endCallAlls()
            pluginCall.resolve()
            break
        case "getDevicePushTokenVoIP":
            pluginCall.resolve(["devicePushTokenVoIP": self.getDevicePushTokenVoIP()])
            break;
        case "silenceEvents":
            guard let silence = options as? Bool else {
                pluginCall.resolve()
                return
            }
            
            self.silenceEvents = silence
            pluginCall.resolve()
            break;
        case "requestNotificationPermission":
            pluginCall.resolve()
            break
         case "requestFullIntentPermission":
            pluginCall.resolve()
            break
        case "hideCallkitIncoming":
            pluginCall.resolve()
            break
        case "endNativeSubsystemOnly":
            pluginCall.resolve()
            break
        case "setAudioRoute":
            pluginCall.resolve()
            break
        default:
            pluginCall.resolve()
        }
    }
    
    @objc public func setDevicePushTokenVoIP(_ deviceToken: String) {
        UserDefaults.standard.set(deviceToken, forKey: devicePushTokenVoIP)
        self.sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_DID_UPDATE_DEVICE_PUSH_TOKEN_VOIP, ["deviceTokenVoIP":deviceToken])
    }
    
    @objc public func getDevicePushTokenVoIP() -> String {
        return UserDefaults.standard.string(forKey: devicePushTokenVoIP) ?? ""
    }
    
    @objc public func getAcceptedCall() -> Data? {
        NSLog("Call data ids \(String(describing: data?.uuid)) \(String(describing: answerCall?.uuid.uuidString))")
        if data?.uuid.lowercased() == answerCall?.uuid.uuidString.lowercased() {
            return data
        }
        return nil
    }
    
    @objc public func checkIsVersionOk(_ pluginCall: CAPPluginCall) {
        var body = [ "isVersionOk": false ]
        if #available(iOS 14.0, *) {
            body["isVersionOk"] = true
        }
        pluginCall.resolve(body)
    }
    
    @objc public func sendPendingAcceptEvent() {
        if (lastIncomingCallEvent != nil) {
            sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_INCOMING, lastIncomingCallEvent)
            lastIncomingCallEvent = nil
        }
        if (lastAcceptCallEvent != nil) {
            sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_ACCEPT, lastAcceptCallEvent)
            lastAcceptCallEvent = nil
        }
    }
    
    @objc public func showCallkitIncoming(_ data: Data, fromPushKit: Bool) {
        self.isFromPushKit = fromPushKit
        if(fromPushKit){
            self.data = data
        }
        if let appDelegate = UIApplication.shared.delegate as? CallkitIncomingAppDelegate {
            var remoteHandle: CXHandle?
            remoteHandle = CXHandle(type: self.getHandleType(data.handleType), value: data.getEncryptHandle())
            appDelegate.reportIncomingCall(data, remoteHandle!) { error in
                if(error == nil) {
                    self.sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_INCOMING, data.toJSON())
                    var url = data.extra["callResponseUrl"] as? String
                    let incomingBody = data.extra["incomingBody"] as? String
                    let sessionToken = data.extra["sessionToken"] as? String
                    NSLog("ACTION_CALL_INCOMING url: \(String(describing: url)), incomingBody: \(String(describing: incomingBody)), sessionToken: \(String(describing: sessionToken))")
                    if (url != nil) {
                        if (sessionToken != nil) {
                            url = url! + "?sessionToken=" + sessionToken!
                        }
                        self.postRequest(url!, incomingBody)
                    }
                }
            }
        }
    }
    
    @objc public func startCall(_ data: Data, fromPushKit: Bool) {
        self.isFromPushKit = fromPushKit
        if(fromPushKit){
            self.data = data
        }
        DispatchQueue.main.async {
            if let appDelegate = UIApplication.shared.delegate as? CallkitIncomingAppDelegate {
                appDelegate.onStartCall(data)
            }
        }
    }
    
    @objc public func muteCall(_ callId: String, isMuted: Bool) {
        guard let callId = UUID(uuidString: callId),
              let call = self.callManager.callWithUUID(uuid: callId) else {
            return
        }
        if call.isMuted == isMuted {
            self.sendMuteEvent(callId.uuidString, isMuted)
        } else {
            self.callManager.muteCall(call: call, isMuted: isMuted)
        }
    }
    
    @objc public func holdCall(_ callId: String, onHold: Bool) {
        if let appDelegate = UIApplication.shared.delegate as? CallkitIncomingAppDelegate {
            appDelegate.onHoldCall(callId, onHold)
        }
    }
    
    @objc public func endCall(_ data: Data) {
        if(self.isFromPushKit){
            self.isFromPushKit = false
            self.sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_ENDED, data.toJSON())
        }
        DispatchQueue.main.async {
            if let appDelegate = UIApplication.shared.delegate as? CallkitIncomingAppDelegate {
                appDelegate.onEndCall(data)
            }
        }
    }
    
    @objc public func connectedCall(_ data: Data) {
        if(self.isFromPushKit){
            self.isFromPushKit = false
        }
        DispatchQueue.main.async {
            if let appDelegate = UIApplication.shared.delegate as? CallkitIncomingAppDelegate {
                appDelegate.onConnectCall(data)
            }
        }
    }
    
    @objc public func activeCalls() -> [[String: Any]] {
        return self.callManager.activeCalls()
    }
    
    @objc public func endAllCalls() {
        self.isFromPushKit = false
        self.callManager.endCallAlls()
    }
    
    public func saveEndCall(_ uuid: String, _ reason: Int) {
        switch reason {
        case 1:
            self.sharedProvider?.reportCall(with: UUID(uuidString: uuid)!, endedAt: Date(), reason: CXCallEndedReason.failed)
            break
        case 2, 6:
            self.sharedProvider?.reportCall(with: UUID(uuidString: uuid)!, endedAt: Date(), reason: CXCallEndedReason.remoteEnded)
            break
        case 3:
            self.sharedProvider?.reportCall(with: UUID(uuidString: uuid)!, endedAt: Date(), reason: CXCallEndedReason.unanswered)
            break
        case 4:
            self.sharedProvider?.reportCall(with: UUID(uuidString: uuid)!, endedAt: Date(), reason: CXCallEndedReason.answeredElsewhere)
            break
        case 5:
            self.sharedProvider?.reportCall(with: UUID(uuidString: uuid)!, endedAt: Date(), reason: CXCallEndedReason.declinedElsewhere)
            break
        default:
            break
        }
    }
    
    
    func endCallNotExist(_ data: Data) {
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(data.duration)) {
            let call = self.callManager.callWithUUID(uuid: UUID(uuidString: data.uuid)!)
            if (call != nil && self.answerCall == nil && self.outgoingCall == nil) {
                self.callEndTimeout(data)
            }
        }
    }
    
    
    
    func callEndTimeout(_ data: Data) {
        self.saveEndCall(data.uuid, 3)
        guard let call = self.callManager.callWithUUID(uuid: UUID(uuidString: data.uuid)!) else {
            return
        }
        sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_TIMEOUT, data.toJSON())
        if let appDelegate = UIApplication.shared.delegate as? CallkitIncomingAppDelegate {
            appDelegate.onTimeOut(call)
        }
    }
    
    func getHandleType(_ handleType: String?) -> CXHandle.HandleType {
        var typeDefault = CXHandle.HandleType.generic
        switch handleType {
        case "number":
            typeDefault = CXHandle.HandleType.phoneNumber
            break
        case "email":
            typeDefault = CXHandle.HandleType.emailAddress
        default:
            typeDefault = CXHandle.HandleType.generic
        }
        return typeDefault
    }
    
    func initCallkitProvider(_ data: Data) {
        if(self.sharedProvider == nil){
            self.sharedProvider = CXProvider(configuration: createConfiguration(data))
            self.sharedProvider?.setDelegate(self, queue: nil)
        }
        self.callManager.setSharedProvider(self.sharedProvider!)
    }
    
    func createConfiguration(_ data: Data) -> CXProviderConfiguration {
        let configuration = CXProviderConfiguration(localizedName: data.appName)
        configuration.supportsVideo = data.supportsVideo
        configuration.maximumCallGroups = data.maximumCallGroups
        configuration.maximumCallsPerCallGroup = data.maximumCallsPerCallGroup
        
        configuration.supportedHandleTypes = [
            CXHandle.HandleType.generic,
            CXHandle.HandleType.emailAddress,
            CXHandle.HandleType.phoneNumber
        ]
        if #available(iOS 11.0, *) {
            configuration.includesCallsInRecents = data.includesCallsInRecents
        }
        if !data.iconName.isEmpty {
            if let image = UIImage(named: data.iconName) {
                configuration.iconTemplateImageData = image.pngData()
            } else {
                print("Unable to load icon \(data.iconName).");
            }
        }
        if !data.ringtonePath.isEmpty || data.ringtonePath != "system_ringtone_default"  {
            configuration.ringtoneSound = data.ringtonePath
        }
        return configuration
    }
    
    func sendDefaultAudioInterruptionNofificationToStartAudioResource(){
        var userInfo : [AnyHashable : Any] = [:]
        let intrepEndeRaw = AVAudioSession.InterruptionType.ended.rawValue
        userInfo[AVAudioSessionInterruptionTypeKey] = intrepEndeRaw
        userInfo[AVAudioSessionInterruptionOptionKey] = AVAudioSession.InterruptionOptions.shouldResume.rawValue
        NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: self, userInfo: userInfo)
    }
    
    func configurAudioSession(){
        if data?.configureAudioSession != false {
            let session = AVAudioSession.sharedInstance()
            do{
                try session.setCategory(AVAudioSession.Category.playAndRecord, options: [
                    .allowBluetoothA2DP,
                    .duckOthers,
                    .allowBluetooth,
                ])
                
                try session.setMode(self.getAudioSessionMode(data?.audioSessionMode))
                try session.setActive(data?.audioSessionActive ?? true)
                try session.setPreferredSampleRate(data?.audioSessionPreferredSampleRate ?? 44100.0)
                try session.setPreferredIOBufferDuration(data?.audioSessionPreferredIOBufferDuration ?? 0.005)
            }catch{
                print(error)
            }
        }
    }
    
    func getAudioSessionMode(_ audioSessionMode: String?) -> AVAudioSession.Mode {
        var mode = AVAudioSession.Mode.default
        switch audioSessionMode {
        case "gameChat":
            mode = AVAudioSession.Mode.gameChat
            break
        case "measurement":
            mode = AVAudioSession.Mode.measurement
            break
        case "moviePlayback":
            mode = AVAudioSession.Mode.moviePlayback
            break
        case "spokenAudio":
            mode = AVAudioSession.Mode.spokenAudio
            break
        case "videoChat":
            mode = AVAudioSession.Mode.videoChat
            break
        case "videoRecording":
            mode = AVAudioSession.Mode.videoRecording
            break
        case "voiceChat":
            mode = AVAudioSession.Mode.voiceChat
            break
        case "voicePrompt":
            if #available(iOS 12.0, *) {
                mode = AVAudioSession.Mode.voicePrompt
            } else {
                // Fallback on earlier versions
            }
            break
        default:
            mode = AVAudioSession.Mode.default
        }
        return mode
    }
    
    public func providerDidReset(_ provider: CXProvider) {
        for call in self.callManager.calls {
            call.endCall()
        }
        self.callManager.removeAllCalls()
    }
    
    public func provider(_ provider: CXProvider, perform action: CXStartCallAction) {
        let call = Call(uuid: action.callUUID, data: self.data!, isOutGoing: true)
        call.handle = action.handle.value
        configurAudioSession()
        call.hasStartedConnectDidChange = { [weak self] in
            self?.sharedProvider?.reportOutgoingCall(with: call.uuid, startedConnectingAt: call.connectData)
        }
        call.hasConnectDidChange = { [weak self] in
            self?.sharedProvider?.reportOutgoingCall(with: call.uuid, connectedAt: call.connectedData)
        }
        self.outgoingCall = call;
        self.callManager.addCall(call)
        self.sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_START, self.data?.toJSON())
        action.fulfill()
    }
    
    public func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        guard let call = self.callManager.callWithUUID(uuid: action.callUUID) else{
            action.fail()
            return
        }
        self.configurAudioSession()
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(1200)) {
            self.configurAudioSession()
        }
        call.hasConnectDidChange = { [weak self] in
            self?.sharedProvider?.reportOutgoingCall(with: call.uuid, connectedAt: call.connectedData)
        }
        self.answerCall = call
        sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_ACCEPT, self.data?.toJSON())
        if let appDelegate = UIApplication.shared.delegate as? CallkitIncomingAppDelegate {
            appDelegate.onAccept(call, action)
        }else {
            action.fulfill()
        }
    }

    public func onEndCall(hasCall: Bool, hasOutgoingCall: Bool, hasAnswerCall: Bool, data: Data?) {
        if (hasCall == false) {
            if(hasAnswerCall == false && hasOutgoingCall == false){
                sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_TIMEOUT, data?.toJSON())
            } else {
                sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_ENDED, data?.toJSON())
            }
            return
        }
        if (hasAnswerCall == false && hasOutgoingCall == false) {
            sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_DECLINE, data?.toJSON())
            var url = data?.extra["callResponseUrl"] as? String
            let declineBody = data?.extra["declineBody"] as? String
            let sessionToken = data?.extra["sessionToken"] as? String
            if (url != nil) {
                if (sessionToken != nil) {
                    url = url! + "?sessionToken=" + sessionToken!
                }
                postRequest(url!, declineBody)
            }
        }else {
            sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_ENDED, data?.toJSON())
        }
    }
    
    
    public func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        guard let call = self.callManager.callWithUUID(uuid: action.callUUID) else {
            self.onEndCall(hasCall: false, hasOutgoingCall: self.outgoingCall != nil, hasAnswerCall: self.answerCall != nil, data: self.data)
            action.fail()
            return
        }
        call.endCall()
        self.callManager.removeCall(call)
        if (self.answerCall == nil && self.outgoingCall == nil) {
            if let appDelegate = UIApplication.shared.delegate as? CallkitIncomingAppDelegate {
                appDelegate.onDecline(call, action)
            } else {
                action.fulfill()
            }
        } else {
            if let appDelegate = UIApplication.shared.delegate as? CallkitIncomingAppDelegate {
                appDelegate.onEnd(call, action)
            } else {
                action.fulfill()
            }
        }
        self.onEndCall(hasCall: true, hasOutgoingCall: self.outgoingCall != nil, hasAnswerCall: self.answerCall != nil, data: self.data)
    }
    
    
    public func provider(_ provider: CXProvider, perform action: CXSetHeldCallAction) {
        guard let call = self.callManager.callWithUUID(uuid: action.callUUID) else {
            action.fail()
            return
        }
        call.isOnHold = action.isOnHold
        call.isMuted = action.isOnHold
        self.callManager.setHold(call: call, onHold: action.isOnHold)
        sendHoldEvent(action.callUUID.uuidString, action.isOnHold)
        action.fulfill()
    }
    
    public func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        guard let call = self.callManager.callWithUUID(uuid: action.callUUID) else {
            action.fail()
            return
        }
        call.isMuted = action.isMuted
        sendMuteEvent(action.callUUID.uuidString, action.isMuted)
        action.fulfill()
    }
    
    public func provider(_ provider: CXProvider, perform action: CXSetGroupCallAction) {
        guard (self.callManager.callWithUUID(uuid: action.callUUID)) != nil else {
            action.fail()
            return
        }
        self.sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_TOGGLE_GROUP, [ "id": action.callUUID.uuidString, "callUUIDToGroupWith" : action.callUUIDToGroupWith?.uuidString])
        action.fulfill()
    }
    
    public func provider(_ provider: CXProvider, perform action: CXPlayDTMFCallAction) {
        guard (self.callManager.callWithUUID(uuid: action.callUUID)) != nil else {
            action.fail()
            return
        }
        self.sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_TOGGLE_DMTF, [ "id": action.callUUID.uuidString, "digits": action.digits, "type": action.type ])
        action.fulfill()
    }
    
    
    public func provider(_ provider: CXProvider, timedOutPerforming action: CXAction) {
        guard let call = self.callManager.callWithUUID(uuid: action.uuid) else {
            action.fail()
            return
        }
        sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_TIMEOUT, self.data?.toJSON())
        if let appDelegate = UIApplication.shared.delegate as? CallkitIncomingAppDelegate {
            appDelegate.onTimeOut(call)
        }
        action.fulfill()
    }
    
    public func provider(_ provider: CXProvider, didActivate audioSession: AVAudioSession) {

        if let appDelegate = UIApplication.shared.delegate as? CallkitIncomingAppDelegate {
            appDelegate.didActivateAudioSession(audioSession)
        }

        if(self.answerCall?.hasConnected ?? false){
            sendDefaultAudioInterruptionNofificationToStartAudioResource()
            return
        }
        if(self.outgoingCall?.hasConnected ?? false){
            sendDefaultAudioInterruptionNofificationToStartAudioResource()
            return
        }
        self.outgoingCall?.startCall(withAudioSession: audioSession) {success in
            if success {
                self.callManager.addCall(self.outgoingCall!)
                self.outgoingCall?.startAudio()
            }
        }
        self.answerCall?.ansCall(withAudioSession: audioSession) { success in
            if success{
                self.answerCall?.startAudio()
            }
        }
        sendDefaultAudioInterruptionNofificationToStartAudioResource()
        configurAudioSession()

        self.sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_TOGGLE_AUDIO_SESSION, [ "isActivate": true ])
    }
    
    public func provider(_ provider: CXProvider, didDeactivate audioSession: AVAudioSession) {
        
        if let appDelegate = UIApplication.shared.delegate as? CallkitIncomingAppDelegate {
            appDelegate.didDeactivateAudioSession(audioSession)
        }

        if self.outgoingCall?.isOnHold ?? false || self.answerCall?.isOnHold ?? false{
            print("Call is on hold")
            return
        }
        self.outgoingCall?.endCall()
        if(self.outgoingCall != nil){
            self.outgoingCall = nil
        }
        self.answerCall?.endCall()
        if(self.answerCall != nil){
            self.answerCall = nil
        }
        self.callManager.removeAllCalls()
        
        self.sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_TOGGLE_AUDIO_SESSION, [ "isActivate": false ])
    }
    
    public func sendMuteEvent(_ id: String, _ isMuted: Bool) {
        self.sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_TOGGLE_MUTE, [ "id": id, "isMuted": isMuted ])
    }
    
    public func sendHoldEvent(_ id: String, _ isOnHold: Bool) {
        self.sendEvent(SwiftFlutterCallkitIncomingPlugin.ACTION_CALL_TOGGLE_HOLD, [ "id": id, "isOnHold": isOnHold ])
    }
    
}
