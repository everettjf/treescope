#if canImport(AppKit) && !targetEnvironment(macCatalyst)
import XCTest
import AppKit
import SwiftUI
import TreescopeProtocol
@testable import TreescopeViewerCore
@testable import TreescopeServer

/// Full pipeline: real AppKit + SwiftUI capture -> serialized over loopback TCP
/// -> decoded by the client. Capture happens on the main thread up front; the
/// server then serves the immutable captured data so the test stays free of
/// runloop dependencies.
final class EndToEndIntegrationTests: XCTestCase {

    private struct Fixture {
        let device: DeviceInfo
        let snapshot: HierarchySnapshot
        let images: [String: SnapshotImage]
    }

    @MainActor
    private func captureFixture() -> Fixture {
        let hosting = NSHostingView(rootView: VStack(spacing: 12) {
            Text("Treescope")
            HStack {
                Text("Left")
                Text("Right")
            }
        })
        hosting.frame = NSRect(x: 0, y: 0, width: 480, height: 320)
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
        content.wantsLayer = true
        content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        content.addSubview(hosting)

        let window = NSWindow(contentRect: content.frame, styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.title = "Demo"
        window.contentView = content

        let engine = CaptureEngine()
        let root = engine.captureWindow(window, options: .default, path: "win0")!
        let snapshot = HierarchySnapshot(device: engine.makeDeviceInfo(), roots: [root])

        var images: [String: SnapshotImage] = [:]
        snapshot.roots.forEach { node in
            node.forEachDepthFirst { n in
                if let sid = n.snapshotID, let img = engine.snapshotImage(nodeID: sid, scale: 1) {
                    images[sid] = img
                }
            }
        }
        return Fixture(device: engine.makeDeviceInfo(), snapshot: snapshot, images: images)
    }

    private func startServer(_ fixture: Fixture) async -> TransportServer {
        let server = TransportServer(serviceName: "TreescopeE2E") { message, respond in
            switch message {
            case .ping:
                respond(.pong)
            case .handshake:
                respond(.handshakeAck(ServerInfo(device: fixture.device, capabilities: [.swiftUI, .snapshots, .highlighting])))
            case .fetchHierarchy:
                respond(.hierarchy(fixture.snapshot))
            case .fetchSnapshot(let id, _):
                if let img = fixture.images[id] { respond(.snapshot(img)) }
                else { respond(.error(code: 404, message: "no image")) }
            default:
                respond(.error(code: 1, message: "unhandled"))
            }
        }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            var resumed = false
            server.onReady = { _ in if !resumed { resumed = true; cont.resume() } }
            server.start(preferredPort: UInt16.random(in: 49_000...49_900))
        }
        return server
    }

    func testFullPipelineCaptureSerializeTransport() async throws {
        let fixture = await captureFixture()
        let server = await startServer(fixture)
        defer { server.stop() }
        let port = try XCTUnwrap(server.port)

        let client = TransportClient()
        try await client.connect(host: "127.0.0.1", port: port)
        defer { client.disconnect() }

        // Handshake.
        let info = try await client.handshake()
        XCTAssertEqual(info.device.osName, "macOS")
        XCTAssertTrue(info.capabilities.contains(.swiftUI))

        // Hierarchy with real SwiftUI nodes transported intact.
        let snapshot = try await client.fetchHierarchy()
        var all: [ViewNode] = []
        snapshot.roots.forEach { $0.forEachDepthFirst { all.append($0) } }

        XCTAssertTrue(all.contains { $0.kind == .nsWindow }, "missing window")
        XCTAssertTrue(all.contains { $0.flags.contains(.hostsSwiftUI) }, "missing hosting view")
        let swiftUITexts = all.filter { $0.kind == .swiftUI && $0.displayName == "Text" }
        XCTAssertEqual(swiftUITexts.count, 3, "expected 3 SwiftUI Texts, got \(swiftUITexts.map(\.label))")
        XCTAssertEqual(Set(swiftUITexts.compactMap(\.label)), ["Treescope", "Left", "Right"])
        XCTAssertTrue(all.contains { $0.kind == .swiftUI && $0.displayName == "VStack" })
        XCTAssertTrue(all.contains { $0.kind == .swiftUI && $0.displayName == "HStack" })

        // Snapshot image round-trips as valid PNG bytes.
        let nodeWithSnapshot = try XCTUnwrap(all.first { $0.snapshotID != nil && $0.kind == .nsView })
        let image = try await client.fetchSnapshot(nodeID: nodeWithSnapshot.snapshotID!)
        let png = try XCTUnwrap(image)
        XCTAssertEqual(png.format, .png)
        XCTAssertGreaterThan(png.data.count, 8)
        // PNG signature.
        XCTAssertEqual(Array(png.data.prefix(4)), [0x89, 0x50, 0x4E, 0x47])
    }

    @MainActor
    func testInspectorSessionDrivesAgainstLiveServer() async throws {
        let fixture = await captureFixture()
        let server = await startServer(fixture)
        defer { server.stop() }
        let port = try XCTUnwrap(server.port)

        let session = InspectorSession()
        await session.connect(host: "127.0.0.1", port: port)

        XCTAssertTrue(session.isConnected)
        XCTAssertNotNil(session.serverInfo)
        XCTAssertNotNil(session.snapshot)
        XCTAssertFalse(session.displayRoots.isEmpty)
        XCTAssertNotNil(session.selectedNodeID, "first root should auto-select")

        // The view model can fetch and cache a node snapshot image.
        var allNodes: [ViewNode] = []
        session.snapshot?.roots.forEach { $0.forEachDepthFirst { allNodes.append($0) } }
        let nodeWithImage = try XCTUnwrap(allNodes.first { $0.snapshotID != nil })
        session.selectedNodeID = nodeWithImage.id
        await session.loadSnapshotImage(for: nodeWithImage.snapshotID!)
        XCTAssertNotNil(session.snapshotImages[nodeWithImage.snapshotID!])

        // Filtering through the view model still finds the captured SwiftUI tree.
        session.searchText = "stack"
        let filtered = session.displayRoots
        var filteredNames: [String] = []
        filtered.forEach { $0.forEachDepthFirst { filteredNames.append($0.displayName) } }
        XCTAssertTrue(filteredNames.contains { $0.contains("Stack") }, "got \(Set(filteredNames))")

        session.disconnect()
        XCTAssertFalse(session.isConnected)
    }

    func testRealBootstrapRespondsToPing() async throws {
        // Validates the public Treescope bootstrap actually starts a live server
        // and answers on the wire (ping needs no main-thread hop).
        let treescope = Treescope.shared
        treescope.logger = nil
        treescope.startServer(preferredPort: UInt16.random(in: 48_000...48_500))
        defer { treescope.stopServer() }

        // Wait briefly for the listener to come up.
        try await Task.sleep(nanoseconds: 300_000_000)
        let port = try XCTUnwrap(treescope.currentPortForTesting)

        let client = TransportClient()
        try await client.connect(host: "127.0.0.1", port: port)
        defer { client.disconnect() }
        try await client.ping()
    }
}
#endif
