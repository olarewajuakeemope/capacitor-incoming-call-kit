import Foundation

@objc public class FlutterCallkitIncoming: NSObject {
    @objc public func echo(_ value: String) -> String {
        print(value)
        return value
    }
}
