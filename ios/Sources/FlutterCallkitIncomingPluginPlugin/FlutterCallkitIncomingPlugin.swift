import Foundation

@objc public class FlutterCallkitIncomingPlugin: NSObject {
    @objc public func echo(_ value: String) -> String {
        print(value)
        return value
    }
}
