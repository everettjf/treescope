import Foundation
import TreescopeServer
import TreescopeViewerCore
import TreescopeProtocol

/// A built-in runtime self-test. When the app is launched with the environment
/// variable `TREESCOPE_PROBE=1`, it connects to its *own* embedded server,
/// fetches the live hierarchy, prints a summary, and exits — proving the whole
/// pipeline (bootstrap → capture → transport → decode) works against a real
/// running app.
enum SelfProbe {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["TREESCOPE_PROBE"] == "1"
    }

    static func runIfRequested() {
        guard isEnabled else { return }
        Task.detached {
            await probe()
        }
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("PROBE FAILED: \(message)\n".utf8))
        exit(2)
    }

    private static func probe() async {
        // Give the window + server a moment to come up.
        for _ in 0..<50 where Treescope.shared.listeningPort == nil {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard let port = Treescope.shared.listeningPort else {
            fail("server never started listening")
        }
        print("PROBE: server on 127.0.0.1:\(port)")

        let client = TransportClient()
        do {
            try await client.connect(host: "127.0.0.1", port: port)
            let info = try await client.handshake()
            print("PROBE: handshake ok — \(info.device.appName) on \(info.device.osName) \(info.device.osVersion)")

            let snapshot = try await client.fetchHierarchy()
            var swiftUICount = 0
            var texts: [String] = []
            var total = 0
            snapshot.roots.forEach { root in
                root.forEachDepthFirst { node in
                    total += 1
                    if node.kind == .swiftUI {
                        swiftUICount += 1
                        if node.displayName == "Text", let label = node.label { texts.append(label) }
                    }
                }
            }
            print("PROBE: captured \(total) nodes, \(swiftUICount) SwiftUI nodes")
            print("PROBE: SwiftUI Text values: \(texts.prefix(10))")

            var histogram: [String: Int] = [:]
            snapshot.roots.forEach { $0.forEachDepthFirst { n in
                if n.kind == .swiftUI { histogram[n.displayName, default: 0] += 1 }
            }}
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
}
