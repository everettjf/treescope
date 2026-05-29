import Foundation
import Network
import TreescopeProtocol

/// A loopback TCP server embedded in the inspected app. It frames
/// `ServerEnvelope` responses and decodes incoming `ClientEnvelope` requests,
/// delegating request handling to a closure (wired to the capture engine).
///
/// Binds to the loopback interface only. On the iOS Simulator this is reachable
/// from a macOS viewer because the simulator shares the host network stack; on
/// device, pair with a USB tunnel. Debug-only by construction.
public final class TransportServer {

    /// Produces a response for a request. Completion may be called asynchronously
    /// (e.g. after hopping to the main thread to read the view hierarchy).
    public typealias RequestHandler = (_ message: ClientMessage,
                                       _ respond: @escaping (ServerMessage) -> Void) -> Void

    private let handler: RequestHandler
    private let queue = DispatchQueue(label: "com.treescope.server")
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: ServerConnection] = [:]
    private let serviceName: String

    public private(set) var port: UInt16?
    public var onLog: ((String) -> Void)?
    public var onReady: ((UInt16) -> Void)?

    public init(serviceName: String, handler: @escaping RequestHandler) {
        self.serviceName = serviceName
        self.handler = handler
    }

    /// Starts listening, scanning forward from `preferredPort` for a free port.
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

        listener.service = NWListener.Service(name: serviceName, type: ProtocolConstants.bonjourServiceType)

        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.port = candidate
                self.log("listening on 127.0.0.1:\(candidate)")
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

    /// Pushes an unsolicited event to all connected viewers.
    public func broadcast(_ message: ServerMessage) {
        queue.async {
            let envelope = ServerEnvelope.push(message)
            for connection in self.connections.values {
                connection.send(envelope)
            }
        }
    }

    public var connectionCount: Int {
        queue.sync { connections.count }
    }

    private func accept(_ nwConnection: NWConnection) {
        let connection = ServerConnection(nwConnection: nwConnection, queue: queue)
        let key = ObjectIdentifier(connection)
        connections[key] = connection
        connection.onRequest = { [weak self] envelope in
            self?.handler(envelope.message) { response in
                connection.send(ServerEnvelope(id: envelope.id, message: response))
            }
        }
        connection.onClose = { [weak self] in
            self?.queue.async { self?.connections[key] = nil }
        }
        connection.onLog = { [weak self] msg in self?.log(msg) }
        connection.start()
        log("client connected (\(connections.count) total)")
    }

    private func log(_ message: String) {
        onLog?("[TreescopeServer] \(message)")
    }
}

/// One accepted client connection: reassembles frames and dispatches requests.
private final class ServerConnection {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private let decoder = FrameDecoder()

    var onRequest: ((ClientEnvelope) -> Void)?
    var onClose: (() -> Void)?
    var onLog: ((String) -> Void)?

    init(nwConnection: NWConnection, queue: DispatchQueue) {
        self.connection = nwConnection
        self.queue = queue
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.onClose?()
            default:
                break
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
                self.decoder.append(data)
                do {
                    while let payload = try self.decoder.next() {
                        let envelope = try JSONDecoder.treescope.decode(ClientEnvelope.self, from: payload)
                        self.onRequest?(envelope)
                    }
                } catch {
                    self.onLog?("decode error: \(error)")
                    self.connection.cancel()
                    return
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

    func send(_ envelope: ServerEnvelope) {
        do {
            let frame = try WireFrame.encode(envelope)
            connection.send(content: frame, completion: .contentProcessed { [weak self] error in
                if let error { self?.onLog?("send error: \(error)") }
            })
        } catch {
            onLog?("encode error: \(error)")
        }
    }
}
