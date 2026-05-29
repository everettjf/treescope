import XCTest
import Foundation
@testable import TreescopeServer
import TreescopeProtocol

/// Full pipeline over the real HTTP/WebSocket transport: start an `HTTPServer`
/// wired to a fixed snapshot, connect with `URLSessionWebSocketTask`, and verify
/// handshake, hierarchy fetch, the `GET /` viewer route, and `GET /snapshot/...`.
final class HTTPEndToEndTests: XCTestCase {

    private func sampleSnapshot() -> HierarchySnapshot {
        let device = DeviceInfo(appName: "TestApp", bundleID: "com.test", processName: "TestApp",
                                osName: "macOS", osVersion: "26.0", deviceModel: "Mac",
                                deviceName: "CI", screenSize: Size(width: 100, height: 100),
                                screenScale: 2, isSimulator: true)
        let child = ViewNode(id: "child", kind: .swiftUI, className: "SwiftUI.Text", displayName: "Text",
                             label: "Hello", frame: Rect(x: 0, y: 0, width: 80, height: 20),
                             bounds: Rect(x: 0, y: 0, width: 80, height: 20),
                             sections: [AttributeSection(title: "Properties",
                                attributes: [Attribute(title: "text", value: .string("Hello"))])])
        let root = ViewNode(id: "root", kind: .window, className: "UIWindow", displayName: "Window",
                            frame: Rect(x: 0, y: 0, width: 100, height: 100),
                            bounds: Rect(x: 0, y: 0, width: 100, height: 100),
                            snapshotID: "root", children: [child])
        return HierarchySnapshot(device: device, roots: [root], timestamp: 1, serverVersion: "0.1.0")
    }

    /// A tiny valid PNG (1x1) so the snapshot route has bytes to serve.
    private let onePixelPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")!

    private func startServer() throws -> (HTTPServer, UInt16) {
        let snapshot = sampleSnapshot()
        let png = onePixelPNG
        let routes = HTTPServer.Routes(
            viewerHTML: { Data("<!doctype html><title>Treescope Test Viewer</title>".utf8) },
            snapshotPNG: { id, _ in id == "root" ? png : nil })

        let server = HTTPServer(serviceName: "TreescopeTest", routes: routes) { message, respond in
            switch message {
            case .ping: respond(.pong)
            case .handshake:
                respond(.handshakeAck(ServerInfo(device: snapshot.device, capabilities: [.snapshots, .swiftUI])))
            case .fetchHierarchy:
                respond(.hierarchy(snapshot))
            case .fetchSnapshot(let nodeID, _):
                respond(.snapshot(SnapshotImage(nodeID: nodeID, format: .png, scale: 2,
                                                pixelSize: Size(width: 1, height: 1), data: png)))
            case .setAttribute(let nodeID, let keyPath, _):
                respond(.attributeResult(nodeID: nodeID, keyPath: keyPath, success: true, message: nil))
            case .highlight(let nodeID):
                respond(.attributeResult(nodeID: nodeID ?? "", keyPath: "highlight", success: true, message: nil))
            }
        }

        let portExp = expectation(description: "listening")
        var boundPort: UInt16 = 0
        server.onReady = { port in boundPort = port; portExp.fulfill() }
        // Use a high preferred port to avoid clashing with a real running instance.
        server.start(preferredPort: 49_000)
        wait(for: [portExp], timeout: 5)
        return (server, boundPort)
    }

    private func openSocket(port: UInt16) -> URLSessionWebSocketTask {
        let task = URLSession.shared.webSocketTask(with: URL(string: "ws://127.0.0.1:\(port)/ws")!)
        task.maximumMessageSize = 16 * 1024 * 1024
        task.resume()
        return task
    }

    private func request(_ task: URLSessionWebSocketTask, id: UInt64, _ message: ClientMessage) async throws -> ServerMessage {
        let env = ClientEnvelope(id: id, message: message)
        let json = try JSONEncoder.treescope.encode(env)
        try await task.send(.string(String(decoding: json, as: UTF8.self)))
        while true {
            let received = try await task.receive()
            let data: Data
            switch received {
            case .string(let s): data = Data(s.utf8)
            case .data(let d): data = d
            @unknown default: continue
            }
            let reply = try JSONDecoder.treescope.decode(ServerEnvelope.self, from: data)
            if reply.id == id { return reply.message }
        }
    }

    func testWebSocketHandshakeAndHierarchy() async throws {
        let (server, port) = try startServer()
        defer { server.stop() }
        let task = openSocket(port: port)
        defer { task.cancel(with: .goingAway, reason: nil) }

        let ack = try await request(task, id: 1, .handshake(ClientInfo(name: "Test", version: "1.0")))
        guard case .handshakeAck(let info) = ack else { return XCTFail("expected ack") }
        XCTAssertEqual(info.device.appName, "TestApp")

        let hierarchy = try await request(task, id: 2, .fetchHierarchy(.default))
        guard case .hierarchy(let snap) = hierarchy else { return XCTFail("expected hierarchy") }
        XCTAssertEqual(snap.totalNodeCount, 2)
        let text = snap.roots.first?.children.first
        XCTAssertEqual(text?.displayName, "Text")
        XCTAssertEqual(text?.label, "Hello")
    }

    func testWebSocketPingAndSetAttribute() async throws {
        let (server, port) = try startServer()
        defer { server.stop() }
        let task = openSocket(port: port)
        defer { task.cancel(with: .goingAway, reason: nil) }

        let pong = try await request(task, id: 1, .ping)
        guard case .pong = pong else { return XCTFail("expected pong") }

        let result = try await request(task, id: 2, .setAttribute(nodeID: "root", keyPath: "alpha", value: .number(0.5)))
        guard case .attributeResult(_, _, let success, _) = result else { return XCTFail("expected result") }
        XCTAssertTrue(success)
    }

    func testViewerHTMLRoute() async throws {
        let (server, port) = try startServer()
        defer { server.stop() }
        let (data, response) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/")!)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("Treescope Test Viewer"))
    }

    func testSnapshotRoute() async throws {
        let (server, port) = try startServer()
        defer { server.stop() }
        let (data, response) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/snapshot/root?scale=2")!)
        let http = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(http.statusCode, 200)
        XCTAssertEqual(http.value(forHTTPHeaderField: "Content-Type"), "image/png")
        XCTAssertEqual(Array(data.prefix(4)), [0x89, 0x50, 0x4E, 0x47]) // PNG magic

        let (_, missing) = try await URLSession.shared.data(from: URL(string: "http://127.0.0.1:\(port)/snapshot/nope")!)
        XCTAssertEqual((missing as? HTTPURLResponse)?.statusCode, 404)
    }
}
