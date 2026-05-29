import XCTest
import TreescopeProtocol
@testable import TreescopeViewerCore

@MainActor
final class InspectorSessionTests: XCTestCase {

    private func makeSnapshot() -> HierarchySnapshot {
        let device = DeviceInfo(appName: "App", bundleID: "x", processName: "App",
                                osName: "macOS", osVersion: "26", deviceModel: "Mac",
                                deviceName: "Test", screenSize: Size(width: 100, height: 100),
                                screenScale: 2, isSimulator: false)
        var system = ViewNode(id: "sys", kind: .uiView, className: "_UISystemView", displayName: "_UISystemView",
                              frame: .zero, bounds: .zero)
        system.flags = [.systemView]
        let label = ViewNode(id: "label", kind: .uiView, className: "UILabel", displayName: "UILabel",
                             label: "Welcome", frame: .zero, bounds: .zero)
        let root = ViewNode(id: "root", kind: .window, className: "UIWindow", displayName: "UIWindow",
                            frame: .zero, bounds: .zero, children: [system, label])
        return HierarchySnapshot(device: device, roots: [root])
    }

    func testDisplayRootsUnfiltered() {
        let session = InspectorSession()
        session.ingestSnapshotForTesting(makeSnapshot())
        let names = collect(session.displayRoots).map(\.displayName)
        XCTAssertTrue(names.contains("UILabel"))
        XCTAssertTrue(names.contains("_UISystemView"))
    }

    func testHideSystemViews() {
        let session = InspectorSession()
        session.ingestSnapshotForTesting(makeSnapshot())
        session.hideSystemViews = true
        let names = collect(session.displayRoots).map(\.displayName)
        XCTAssertTrue(names.contains("UILabel"))
        XCTAssertFalse(names.contains("_UISystemView"), "system view should be hidden")
    }

    func testSearchKeepsMatchAndAncestors() {
        let session = InspectorSession()
        session.ingestSnapshotForTesting(makeSnapshot())
        session.searchText = "welcome"
        let nodes = collect(session.displayRoots)
        let names = nodes.map(\.displayName)
        XCTAssertTrue(names.contains("UIWindow"), "ancestor kept")
        XCTAssertTrue(names.contains("UILabel"), "match kept")
        XCTAssertFalse(names.contains("_UISystemView"), "non-match pruned")
    }

    func testSelectedNodeLookup() {
        let session = InspectorSession()
        session.ingestSnapshotForTesting(makeSnapshot())
        session.selectedNodeID = "label"
        XCTAssertEqual(session.selectedNode?.label, "Welcome")
    }

    private func collect(_ roots: [ViewNode]) -> [ViewNode] {
        var out: [ViewNode] = []
        roots.forEach { $0.forEachDepthFirst { out.append($0) } }
        return out
    }
}
