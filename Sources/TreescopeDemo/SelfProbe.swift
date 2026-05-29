import Foundation
import TreescopeServer
import TreescopeProtocol

/// A built-in runtime self-test. When the app is launched with the environment
/// variable `TREESCOPE_PROBE=1`, it connects to its *own* embedded server over a
/// WebSocket, fetches the live hierarchy, prints a summary, and exits — proving
/// the whole pipeline (bootstrap → capture → HTTP/WS transport → decode) works
/// against a real running app.
enum SelfProbe {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["TREESCOPE_PROBE"] == "1"
    }

    static func runIfRequested() {
        guard isEnabled else { return }
        Task.detached { await probe() }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("PROBE FAILED: \(message)\n".utf8))
        exit(2)
    }

    private static func probe() async {
        for _ in 0..<50 where Treescope.shared.listeningPort == nil {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard let port = Treescope.shared.listeningPort else {
            fail("server never started listening")
        }
        print("PROBE: server on http://127.0.0.1:\(port)")

        guard let url = URL(string: "ws://127.0.0.1:\(port)/ws") else { fail("bad url") }
        let task = URLSession.shared.webSocketTask(with: url)
        task.maximumMessageSize = 64 * 1024 * 1024
        task.resume()

        do {
            // Handshake.
            let info = try await request(task, id: 1, .handshake(
                ClientInfo(name: "Treescope SelfProbe", version: ProtocolConstants.version)))
            guard case .handshakeAck(let server) = info else { fail("no handshake ack") }
            print("PROBE: handshake ok — \(server.device.appName) on \(server.device.osName) \(server.device.osVersion)")

            // Hierarchy.
            let response = try await request(task, id: 2, .fetchHierarchy(.default))
            guard case .hierarchy(let snapshot) = response else { fail("no hierarchy") }

            var total = 0, swiftUICount = 0, layerCount = 0
            var histogram: [String: Int] = [:]
            snapshot.roots.forEach { $0.forEachDepthFirst { n in
                total += 1
                if n.kind == .swiftUI { swiftUICount += 1; histogram[n.displayName, default: 0] += 1 }
                if n.kind == .caLayer { layerCount += 1 }
            }}
            print("PROBE: captured \(total) nodes — \(swiftUICount) SwiftUI, \(layerCount) CALayer")
            let top = histogram.sorted { $0.value > $1.value }.prefix(20)
            print("PROBE: SwiftUI node types: \(top.map { "\($0.key)=\($0.value)" }.joined(separator: ", "))")

            guard total > 0 else { fail("captured zero nodes") }
            guard swiftUICount > 0 else { fail("captured no SwiftUI nodes — reflection not wired") }

            print("PROBE SUCCEEDED ✅")
            exit(0)
        } catch {
            fail("client error: \(error)")
        }
    }

    /// Sends one request envelope and waits for the matching response.
    private static func request(_ task: URLSessionWebSocketTask, id: UInt64,
                                _ message: ClientMessage) async throws -> ServerMessage {
        let envelope = ClientEnvelope(id: id, message: message)
        let json = try JSONEncoder.treescope.encode(envelope)
        try await task.send(.string(String(decoding: json, as: UTF8.self)))
        // Skip any unsolicited pushes (id == 0) until our id arrives.
        while true {
            let message = try await task.receive()
            let data: Data
            switch message {
            case .string(let s): data = Data(s.utf8)
            case .data(let d): data = d
            @unknown default: continue
            }
            let reply = try JSONDecoder.treescope.decode(ServerEnvelope.self, from: data)
            if reply.id == id { return reply.message }
        }
    }
}
