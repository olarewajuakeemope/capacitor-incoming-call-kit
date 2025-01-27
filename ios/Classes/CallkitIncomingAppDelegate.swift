//
//  CallkitIncomingAppDelegate.swift
//  flutter_callkit_incoming
//
//  Created by Hien Nguyen on 05/01/2024.
//

import Foundation
import AVFAudio
import CallKit


public protocol CallkitIncomingAppDelegate : NSObjectProtocol {
    
    func onTimeOut(_ call: Call)
    
    func onEndCall(_ data: Data)
    
    func onStartCall(_ data: Data)
    
    func onConnectCall(_ data: Data)
    
    func onHoldCall(_ callId: String, _ onHold: Bool)
    
    func onEnd(_ call: Call, _ action: CXEndCallAction)
    
    func onDecline(_ call: Call, _ action: CXEndCallAction)
    
    func onAccept(_ call: Call, _ action: CXAnswerCallAction)

    func didActivateAudioSession(_ audioSession: AVAudioSession)
    
    func didDeactivateAudioSession(_ audioSession: AVAudioSession)
    
    func reportIncomingCall(_ data: Data, _ remoteHandle: CXHandle?, completion: ((Error?) -> Void)?)
    
}
