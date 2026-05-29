import Foundation
import Network
import TreescopeProtocol

public enum TransportError: Error, LocalizedError {
    case notConnected
    case connectionFailed(String)
    case timedOut
    case unexpectedResponse(ServerMessage)

    public var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to a Treescope server."
        case .connectionFailed(let m): return "Connection failed: \(m)"
        case .timedOut: return "The request timed out."
        case .unexpectedResponse: return "The server returned an unexpected response."
        }
    }
}

/// Low-level async client that talks to a `TransportServer`. Correlates
/// responses to requests by envelope id and surfaces unsolicited pushes.
public final class TransportClient {

    public enum State: Equatable {
        case idle
        case connecting
        case connected
        case failed(String)
        case cancelled
    }

    private let queue = DispatchQueue(label: "com.treescope.client")
    private var connection: NWConnection?
    private let decoder = FrameDecoder()

    private var nextID: UInt64 = 1
    private var pending: [UInt64: CheckedContinuation<ServerMessage, Error>] = [:]
    private var connectContinuation: CheckedContinuation<Void, Error>?

    public private(set) var state: State = .idle
    public var onStateChange: ((State) -> Void)?
    public var onEvent: ((ServerEvent) -> Void)?
    public var onLog: ((String) -> Void)?

    public init() {}

    // MARK: Connect

    public func connect(host: String, port: UInt16) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async {
                let params = NWParameters.tcp
                params.allowLocalEndpointReuse = true
                let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host),
                                                   port: NWEndpoint.Port(rawValue: port)!)
                let connection = NWConnection(to: endpoint, using: params)
                self.connection = connection
                self.connectContinuation = cont
                self.setState(.connecting)

                connection.stateUpdateHandler = { [weak self] nwState in
                    guard let self else { return }
                    switch nwState {
                    case .ready:
                        self.setState(.connected)
                        self.connectContinuation?.resume()
                        self.connectContinuation = nil
                        self.receive()
                    case .failed(let error):
                        self.setState(.failed(error.localizedDescription))
                        self.connectContinuation?.resume(throwing: TransportError.connectionFailed(error.localizedDescription))
                        self.connectContinuation = nil
                        self.failAllPending(TransportError.connectionFailed(error.localizedDescription))
                    case .cancelled:
                        self.setState(.cancelled)
                        self.failAllPending(TransportError.notConnected)
                    default:
                        break
                    }
                }
                connection.start(queue: self.queue)
            }
        }
    }

    /// Connects to an already-resolved Bonjour endpoint.
    public func connect(to endpoint: NWEndpoint) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async {
                let params = NWParameters.tcp
                params.allowLocalEndpointReuse = true
                let connection = NWConnection(to: endpoint, using: params)
                self.connection = connection
                self.connectContinuation = cont
                self.setState(.connecting)
                connection.stateUpdateHandler = { [weak self] nwState in
                    guard let self else { return }
                    switch nwState {
                    case .ready:
                        self.setState(.connected)
                        self.connectContinuation?.resume(); self.connectContinuation = nil
                        self.receive()
                    case .failed(let error):
                        self.setState(.failed(error.localizedDescription))
                        self.connectContinuation?.resume(throwing: TransportError.connectionFailed(error.localizedDescription))
                        self.connectContinuation = nil
                        self.failAllPending(TransportError.connectionFailed(error.localizedDescription))
                    case .cancelled:
                        self.setState(.cancelled)
                        self.failAllPending(TransportError.notConnected)
                    default:
                        break
                    }
                }
                connection.start(queue: self.queue)
            }
        }
    }

    public func disconnect() {
        queue.async {
            self.connection?.cancel()
            self.connection = nil
        }
    }

    // MARK: Request / response

    @discardableResult
    public func send(_ message: ClientMessage, timeout: TimeInterval = 15) async throws -> ServerMessage {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<ServerMessage, Error>) in
            queue.async {
                guard let connection = self.connection, self.state == .connected else {
                    cont.resume(throwing: TransportError.notConnected)
                    return
                }
                let id = self.nextID
                self.nextID &+= 1
                self.pending[id] = cont

                do {
                    let frame = try WireFrame.encode(ClientEnvelope(id: id, message: message))
                    connection.send(content: frame, completion: .contentProcessed { error in
                        if let error {
                            self.queue.async {
                                if let c = self.pending.removeValue(forKey: id) {
                                    c.resume(throwing: TransportError.connectionFailed(error.localizedDescription))
                                }
                            }
                        }
                    })
                } catch {
                    self.pending[id] = nil
                    cont.resume(throwing: error)
                    return
                }

                // Timeout guard.
                self.queue.asyncAfter(deadline: .now() + timeout) {
                    if let c = self.pending.removeValue(forKey: id) {
                        c.resume(throwing: TransportError.timedOut)
                    }
                }
            }
        }
    }

    // MARK: Receive loop

    private func receive() {
        connection?.receive(minimumIncompleteLength: 1, maximumLength: 1 << 20) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.decoder.append(data)
                do {
                    while let payload = try self.decoder.next() {
                        let envelope = try JSONDecoder.treescope.decode(ServerEnvelope.self, from: payload)
                        self.handle(envelope)
                    }
                } catch {
                    self.onLog?("decode error: \(error)")
                }
            }
            if isComplete || error != nil {
                self.setState(.cancelled)
                self.failAllPending(TransportError.notConnected)
                return
            }
            self.receive()
        }
    }

    private func handle(_ envelope: ServerEnvelope) {
        if envelope.id == 0 {
            if case .event(let event) = envelope.message {
                onEvent?(event)
            }
            return
        }
        if let cont = pending.removeValue(forKey: envelope.id) {
            cont.resume(returning: envelope.message)
        }
    }

    private func failAllPending(_ error: Error) {
        let conts = pending.values
        pending.removeAll()
        for c in conts { c.resume(throwing: error) }
    }

    private func setState(_ newState: State) {
        state = newState
        onStateChange?(newState)
    }
}
