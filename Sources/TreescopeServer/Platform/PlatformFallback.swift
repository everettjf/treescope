import Foundation
import TreescopeProtocol

// Stubs used only on platforms that have neither UIKit nor AppKit, so the
// engine still compiles. The shipped products all target platforms with one.
#if !canImport(UIKit) && !(canImport(AppKit) && !targetEnvironment(macCatalyst))
extension CaptureEngine {
    func makeDeviceInfo() -> DeviceInfo {
        let info = ProcessInfo.processInfo
        return DeviceInfo(appName: info.processName, bundleID: "unknown", processName: info.processName,
                          osName: "unknown", osVersion: "0", deviceModel: "unknown", deviceName: "unknown",
                          screenSize: .zero, screenScale: 1, isSimulator: false)
    }
    func captureRoots(options: HierarchyOptions) -> [ViewNode] { [] }
    func renderSnapshot(object: AnyObject, nodeID: String, scale: Double) -> SnapshotImage? { nil }
    func setAttribute(on object: AnyObject, keyPath: String, value: AttributeValue) -> (Bool, String?) { (false, "unsupported platform") }
    func highlight(nodeID: String?) -> Bool { false }
}
#endif
