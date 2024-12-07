import Foundation
import Capacitor

/**
 * Please read the Capacitor iOS Plugin Development Guide
 * here: https://capacitorjs.com/docs/plugins/ios
 */
@objc(FlutterCallkitIncomingPlugin)
public class FlutterCallkitIncomingPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "FlutterCallkitIncomingPlugin"
    public let jsName = "FlutterCallkitIncoming"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "echo", returnType: CAPPluginReturnPromise)
    ]
    private let implementation = FlutterCallkitIncoming()

    @objc func echo(_ call: CAPPluginCall) {
        let value = call.getString("value") ?? ""
        call.resolve([
            "value": implementation.echo(value)
        ])
    }
}
