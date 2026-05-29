import Foundation
import Network
import TreescopeProtocol

/// A loopback HTTP/1.1 + WebSocket server embedded in the inspected app.
///
/// - `GET /` (and `/index.html`) serves the browser viewer.
/// - `GET /snapshot/{nodeID}?scale=2` serves a rendered PNG of a node.
/// - `GET /ws` upgrades to a WebSocket carrying the JSON inspector protocol.
///
/// Binds to the loopback interface only. On the iOS Simulator this is reachable
/// from a browser on the host Mac because the simulator shares the host network
/// stack. Zero third-party dependencies (Network.framework + CryptoKit only).
public final class HTTPServer {

    /// Produces a response for a decoded request. The completion may fire
    /// asynchronously (e.g. after hopping to the main thread to read views).
    public typealias RequestHandler = (_ message: ClientMessage,
                                       _ respond: @escaping (ServerMessage) -> Void) -> Void

    /// Static-route providers wired to the capture engine.
    public struct Routes {
        public var viewerHTML: () -> Data
        public var snapshotPNG: (_ nodeID: String, _ scale: Double) -> Data?
        public init(viewerHTML: @escaping () -> Data,
                    snapshotPNG: @escaping (_ nodeID: String, _ scale: Double) -> Data?) {
            self.viewerHTML = viewerHTML
            self.snapshotPNG = snapshotPNG
        }
    }

    private let handler: RequestHandler
    private let routes: Routes
    private let serviceName: String
    private let queue = DispatchQueue(label: "com.treescope.http")
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: Connection] = [:]

    public private(set) var port: UInt16?
    public var onLog: ((String) -> Void)?
    public var onReady: ((UInt16) -> Void)?

    public init(serviceName: String, routes: Routes, handler: @escaping RequestHandler) {
        self.serviceName = serviceName
        self.routes = routes
        self.handler = handler
    }

    // MARK: Lifecycle

    public func start(preferredPort: UInt16 = ProtocolConstants.defaultPort) {
        queue.async { self.tryStart(port: preferredPort, attemptsLeft: ProtocolConstants.portScanCount) }
    }

    private func tryStart(port candidate: UInt16, attemptsLeft: Int) {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        params.requiredInterfaceType = .loopback
        params.includePeerToPeer = false

        guard let nwPort = NWEndpoint.Port(rawValue: candidate) else { return }
        let listener: NWListener
        do {
            listener = try NWListener(using: params, on: nwPort)
        } catch {
            if attemptsLeft > 1 {
                tryStart(port: candidate &+ 1, attemptsLeft: attemptsLeft - 1)
            } else {
                log("failed to create listener: \(error)")
            }
            return
        }

        // Advertise over Bonjour too — harmless, occasionally handy for tooling.
        listener.service = NWListener.Service(name: serviceName, type: ProtocolConstants.bonjourServiceType)

        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.port = candidate
                self.log("listening on http://127.0.0.1:\(candidate)")
                self.onReady?(candidate)
            case .failed(let error):
                self.log("listener failed on \(candidate): \(error)")
                listener?.cancel()
                if attemptsLeft > 1 {
                    self.tryStart(port: candidate &+ 1, attemptsLeft: attemptsLeft - 1)
                }
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] nwConnection in
            self?.accept(nwConnection)
        }

        self.listener = listener
        listener.start(queue: queue)
    }

    public func stop() {
        queue.async {
            for connection in self.connections.values { connection.cancel() }
            self.connections.removeAll()
            self.listener?.cancel()
            self.listener = nil
            self.port = nil
        }
    }

    /// Pushes an unsolicited event to all connected WebSocket viewers.
    public func broadcast(_ message: ServerMessage) {
        queue.async {
            let envelope = ServerEnvelope.push(message)
            guard let json = try? JSONEncoder.treescope.encode(envelope) else { return }
            let text = String(decoding: json, as: UTF8.self)
            for connection in self.connections.values where connection.isWebSocket {
                connection.sendWebSocketText(text)
            }
        }
    }

    public var connectionCount: Int { queue.sync { connections.count } }

    private func accept(_ nwConnection: NWConnection) {
        let connection = Connection(nwConnection: nwConnection, queue: queue,
                                    routes: routes, handler: handler)
        let key = ObjectIdentifier(connection)
        connections[key] = connection
        connection.onClose = { [weak self] in
            self?.queue.async { self?.connections[key] = nil }
        }
        connection.onLog = { [weak self] msg in self?.log(msg) }
        connection.start()
    }

    private func log(_ message: String) { onLog?("[Treescope] \(message)") }
}

// MARK: - One client connection

/// Handles a single TCP connection: parses one HTTP request, then either serves
/// a static response and closes, or upgrades to WebSocket and runs the protocol.
private final class Connection {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let routes: HTTPServer.Routes
    private let handler: HTTPServer.RequestHandler

    private enum Mode { case http, webSocket }
    private var mode: Mode = .http
    private var httpBuffer = Data()
    private let wsDecoder = WebSocket.Decoder()

    var onClose: (() -> Void)?
    var onLog: ((String) -> Void)?

    var isWebSocket: Bool { mode == .webSocket }

    init(nwConnection: NWConnection, queue: DispatchQueue,
         routes: HTTPServer.Routes, handler: @escaping HTTPServer.RequestHandler) {
        self.connection = nwConnection
        self.queue = queue
        self.routes = routes
        self.handler = handler
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.onClose?()
            default: break
            }
        }
        connection.start(queue: queue)
        receive()
    }

    func cancel() { connection.cancel() }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                switch self.mode {
                case .http: self.feedHTTP(data)
                case .webSocket: self.feedWebSocket(data)
                }
            }
            if isComplete || error != nil {
                self.onClose?()
                self.connection.cancel()
                return
            }
            self.receive()
        }
    }

    // MARK: HTTP

    private func feedHTTP(_ data: Data) {
        httpBuffer.append(data)
        // Wait for the end of the header block.
        guard let range = httpBuffer.range(of: Data("\r\n\r\n".utf8)) else {
            if httpBuffer.count > 64 * 1024 { close() } // runaway header guard
            return
        }
        let headerData = httpBuffer.subdata(in: httpBuffer.startIndex..<range.lowerBound)
        let headerBlock = String(decoding: headerData, as: UTF8.self)
        guard let request = HTTPRequest.parse(headerBlock: headerBlock) else {
            send(HTTPResponse.notFound(), thenClose: true)
            return
        }

        if request.isWebSocketUpgrade {
            upgradeToWebSocket(request)
        } else {
            route(request)
        }
    }

    private func route(_ request: HTTPRequest) {
        let path = request.path
        if path == "/" || path == "/index.html" {
            send(HTTPResponse.ok(routes.viewerHTML(), contentType: "text/html; charset=utf-8"), thenClose: true)
        } else if path == "/healthz" {
            send(HTTPResponse.ok(Data("ok".utf8), contentType: "text/plain"), thenClose: true)
        } else if path.hasPrefix("/snapshot/") {
            let id = String(path.dropFirst("/snapshot/".count))
            let scale = Double(request.query["scale"] ?? "") ?? 2
            if let png = routes.snapshotPNG(id, scale) {
                send(HTTPResponse.ok(png, contentType: "image/png"), thenClose: true)
            } else {
                send(HTTPResponse.notFound(), thenClose: true)
            }
        } else {
            send(HTTPResponse.notFound(), thenClose: true)
        }
    }

    // MARK: WebSocket

    private func upgradeToWebSocket(_ request: HTTPRequest) {
        guard let key = request.header("sec-websocket-key") else {
            send(HTTPResponse.notFound(), thenClose: true)
            return
        }
        let accept = WebSocket.acceptKey(for: key)
        send(HTTPResponse.switchingProtocols(acceptKey: accept), thenClose: false)
        mode = .webSocket
        onLog?("viewer connected")
        // Any bytes already buffered past the header block belong to the WS stream.
        if let range = httpBuffer.range(of: Data("\r\n\r\n".utf8)) {
            let leftover = httpBuffer.subdata(in: range.upperBound..<httpBuffer.endIndex)
            httpBuffer = Data()
            if !leftover.isEmpty { feedWebSocket(leftover) }
        }
    }

    private func feedWebSocket(_ data: Data) {
        wsDecoder.append(data)
        do {
            while let message = try wsDecoder.next() {
                switch message {
                case .text(let string):
                    handleWebSocketText(string)
                case .binary:
                    break // protocol is text/JSON only
                case .ping(let payload):
                    sendRaw(WebSocket.encodePong(payload))
                case .pong:
                    break
                case .close:
                    sendRaw(WebSocket.encodeClose())
                    close()
                    return
                }
            }
        } catch {
            onLog?("websocket decode error: \(error)")
            close()
        }
    }

    private func handleWebSocketText(_ string: String) {
        guard let data = string.data(using: .utf8),
              let envelope = try? JSONDecoder.treescope.decode(ClientEnvelope.self, from: data) else {
            onLog?("bad client frame")
            return
        }
        let id = envelope.id
        handler(envelope.message) { [weak self] response in
            self?.queue.async {
                guard let self else { return }
                let reply = ServerEnvelope(id: id, message: response)
                guard let json = try? JSONEncoder.treescope.encode(reply) else { return }
                self.sendWebSocketText(String(decoding: json, as: UTF8.self))
            }
        }
    }

    func sendWebSocketText(_ text: String) {
        sendRaw(WebSocket.encodeText(text))
    }

    // MARK: Low-level send

    private func send(_ data: Data, thenClose: Bool) {
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error { self?.onLog?("send error: \(error)") }
            if thenClose { self?.close() }
        })
    }

    private func sendRaw(_ data: Data) {
        connection.send(content: data, completion: .contentProcessed { [weak self] error in
            if let error { self?.onLog?("send error: \(error)") }
        })
    }

    private func close() {
        onClose?()
        connection.cancel()
    }
}
