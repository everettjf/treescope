import Foundation
import TreescopeProtocol

/// The public entry point for the in-app inspector runtime.
///
/// ## Usage
/// Call `Treescope.start()` once, early in your app's lifecycle — typically
/// guarded so it only runs in Debug builds:
///
/// ```swift
/// #if DEBUG
/// Treescope.start()
/// #endif
/// ```
///
/// Then open `http://127.0.0.1:47761` in any browser to inspect the running app.
///
/// This is intended to be linked **Debug-only**. Because it is excluded from
/// Release builds, any reliance on private SwiftUI debug data carries no App
/// Store review risk.
public final class Treescope {

    public static let shared = Treescope()

    private let engine = CaptureEngine()
    private var server: HTTPServer?
    private let lock = NSLock()

    /// Emits diagnostic log lines (defaults to `print`). Set to `nil` to silence.
    public var logger: ((String) -> Void)? = { print($0) }

    public private(set) var isRunning = false

    /// The bound port once the server is listening, else nil.
    public var listeningPort: UInt16? { server?.port }

    /// Internal alias used by tests.
    var currentPortForTesting: UInt16? { server?.port }

    private init() {}

    // MARK: Lifecycle

    /// Starts the inspector server. Idempotent.
    @discardableResult
    public static func start(preferredPort: UInt16 = ProtocolConstants.defaultPort) -> Treescope {
        shared.startServer(preferredPort: preferredPort)
        return shared
    }

    public static func stop() { shared.stopServer() }

    public func startServer(preferredPort: UInt16 = ProtocolConstants.defaultPort) {
        lock.lock(); defer { lock.unlock() }
        guard !isRunning else { return }

        let routes = HTTPServer.Routes(
            viewerHTML: { [weak self] in self?.loadViewerHTML() ?? Data(Self.fallbackHTML.utf8) },
            snapshotPNG: { [weak self] nodeID, scale in
                guard let self else { return nil }
                return self.mainSync { self.engine.snapshotImage(nodeID: nodeID, scale: scale)?.data }
            })

        let server = HTTPServer(serviceName: engineServiceName(), routes: routes) { [weak self] message, respond in
            self?.handle(message, respond: respond)
        }
        server.onLog = { [weak self] in self?.logger?($0) }
        server.onReady = { [weak self] port in
            self?.logger?("[Treescope] Ready. Open http://127.0.0.1:\(port) in your browser.")
        }
        self.server = server
        self.isRunning = true
        server.start(preferredPort: preferredPort)
        logger?("[Treescope] Starting inspector server…")
    }

    public func stopServer() {
        lock.lock(); defer { lock.unlock() }
        server?.stop()
        server = nil
        isRunning = false
    }

    /// Notifies connected viewers that the hierarchy likely changed so they can
    /// refresh. Safe to call from any thread.
    public func notifyHierarchyChanged() {
        server?.broadcast(.event(.hierarchyChanged))
    }

    // MARK: Request handling

    private func handle(_ message: ClientMessage, respond: @escaping (ServerMessage) -> Void) {
        switch message {
        case .ping:
            respond(.pong)

        case .handshake:
            onMain {
                let info = ServerInfo(device: self.engine.makeDeviceInfo(),
                                      capabilities: self.engine.capabilities)
                respond(.handshakeAck(info))
            }

        case .fetchHierarchy(let options):
            onMain {
                let snapshot = self.engine.captureHierarchy(options: options)
                respond(.hierarchy(snapshot))
            }

        case .fetchSnapshot(let nodeID, let scale):
            onMain {
                if let image = self.engine.snapshotImage(nodeID: nodeID, scale: scale) {
                    respond(.snapshot(image))
                } else {
                    respond(.error(code: 404, message: "no snapshot for \(nodeID)"))
                }
            }

        case .setAttribute(let nodeID, let keyPath, let value):
            onMain {
                let (ok, msg) = self.engine.applyAttribute(nodeID: nodeID, keyPath: keyPath, value: value)
                respond(.attributeResult(nodeID: nodeID, keyPath: keyPath, success: ok, message: msg))
            }

        case .highlight(let nodeID):
            onMain {
                let ok = self.engine.highlight(nodeID: nodeID)
                respond(.attributeResult(nodeID: nodeID ?? "", keyPath: "highlight", success: ok, message: nil))
            }
        }
    }

    // MARK: Resources

    private func loadViewerHTML() -> Data? {
        guard let url = Bundle.module.url(forResource: "viewer", withExtension: "html") else { return nil }
        return try? Data(contentsOf: url)
    }

    static let fallbackHTML = """
    <!doctype html><html><body style="font-family:sans-serif;background:#1e1e1e;color:#eee;padding:2rem">
    <h1>Treescope viewer asset missing</h1><p>Rebuild the package with the bundled viewer.</p></body></html>
    """

    // MARK: Threading

    private func onMain(_ work: @escaping () -> Void) {
        if Thread.isMainThread { work() } else { DispatchQueue.main.async(execute: work) }
    }

    private func mainSync<T>(_ work: () -> T) -> T {
        if Thread.isMainThread { return work() }
        return DispatchQueue.main.sync(execute: work)
    }

    private func engineServiceName() -> String {
        (Bundle.main.infoDictionary?["CFBundleName"] as? String) ?? ProcessInfo.processInfo.processName
    }
}
