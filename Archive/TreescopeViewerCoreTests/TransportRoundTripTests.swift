import XCTest
import TreescopeProtocol
@testable import TreescopeViewerCore
@testable import TreescopeServer

final class TransportRoundTripTests: XCTestCase {

    /// Spins up a server with the given handler and returns it once listening.
    private func startServer(handler: @escaping TransportServer.RequestHandler) async -> TransportServer {
        let server = TransportServer(serviceName: "TreescopeTest", handler: handler)
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            var resumed = false
            server.onReady = { _ in
                if !resumed { resumed = true; cont.resume() }
            }
            server.start(preferredPort: UInt16.random(in: 49_000...49_900))
        }
        return server
    }

    private func sampleSnapshot() -> HierarchySnapshot {
        let device = DeviceInfo(appName: "Demo", bundleID: "com.x", processName: "Demo",
                                osName: "macOS", osVersion: "26.0", deviceModel: "Mac",
                                deviceName: "Test", screenSize: Size(width: 100, height: 100),
                                screenScale: 2, isSimulator: false)
        let node = ViewNode(id: "root", kind: .nsView, className: "NSView", displayName: "NSView",
                            frame: Rect(x: 0, y: 0, width: 100, height: 100),
                            bounds: Rect(x: 0, y: 0, width: 100, height: 100))
        return HierarchySnapshot(device: device, roots: [node])
    }

    func testPingPong() async throws {
        let server = await startServer { message, respond in
            if case .ping = message { respond(.pong) } else { respond(.error(code: 1, message: "?")) }
        }
        defer { server.stop() }
        let port = try XCTUnwrap(server.port)

        let client = TransportClient()
        try await client.connect(host: "127.0.0.1", port: port)
        defer { client.disconnect() }
        try await client.ping() // throws if not pong
    }

    func testHandshakeAndHierarchy() async throws {
        let snapshot = sampleSnapshot()
        let device = snapshot.device
        let server = await startServer { message, respond in
            switch message {
            case .handshake:
                respond(.handshakeAck(ServerInfo(device: device, capabilities: [.swiftUI, .snapshots])))
            case .fetchHierarchy:
                respond(.hierarchy(snapshot))
            default:
                respond(.error(code: 1, message: "unhandled"))
            }
        }
        defer { server.stop() }
        let port = try XCTUnwrap(server.port)

        let client = TransportClient()
        try await client.connect(host: "127.0.0.1", port: port)
        defer { client.disconnect() }

        let info = try await client.handshake()
        XCTAssertEqual(info.device.appName, "Demo")
        XCTAssertTrue(info.capabilities.contains(.swiftUI))

        let fetched = try await client.fetchHierarchy()
        XCTAssertEqual(fetched.totalNodeCount, 1)
        XCTAssertEqual(fetched.roots.first?.displayName, "NSView")
    }

    func testConcurrentRequestsCorrelateCorrectly() async throws {
        // Server echoes the request id back inside a log event-free response so
        // we can verify the client matched responses to the right requests.
        let server = await startServer { message, respond in
            if case .fetchSnapshot(let nodeID, _) = message {
                let img = SnapshotImage(nodeID: nodeID, format: .png, scale: 1,
                                        pixelSize: .zero, data: Data(nodeID.utf8))
                // Respond after a small jittered delay to interleave responses.
                let delay = Double.random(in: 0...0.05)
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) { respond(.snapshot(img)) }
            } else {
                respond(.error(code: 1, message: "?"))
            }
        }
        defer { server.stop() }
        let port = try XCTUnwrap(server.port)

        let client = TransportClient()
        try await client.connect(host: "127.0.0.1", port: port)
        defer { client.disconnect() }

        try await withThrowingTaskGroup(of: (String, String).self) { group in
            for i in 0..<20 {
                let nodeID = "node-\(i)"
                group.addTask {
                    let image = try await client.fetchSnapshot(nodeID: nodeID)
                    let echoed = String(data: image?.data ?? Data(), encoding: .utf8) ?? ""
                    return (nodeID, echoed)
                }
            }
            for try await (requested, echoed) in group {
                XCTAssertEqual(requested, echoed, "response correlated to wrong request")
            }
        }
    }

    func testRequestFailsWhenNotConnected() async {
        let client = TransportClient()
        do {
            _ = try await client.ping()
            XCTFail("expected failure")
        } catch {
            XCTAssertTrue(error is TransportError)
        }
    }
}
