import Foundation
import TreescopeProtocol

/// Typed request helpers that unwrap the matching response case.
public extension TransportClient {

    func handshake(clientName: String = "Treescope Viewer",
                   clientVersion: String = ProtocolConstants.version) async throws -> ServerInfo {
        let response = try await send(.handshake(ClientInfo(name: clientName, version: clientVersion)))
        switch response {
        case .handshakeAck(let info): return info
        case .error(_, let message): throw TransportError.connectionFailed(message)
        default: throw TransportError.unexpectedResponse(response)
        }
    }

    func fetchHierarchy(options: HierarchyOptions = .default) async throws -> HierarchySnapshot {
        let response = try await send(.fetchHierarchy(options), timeout: 30)
        switch response {
        case .hierarchy(let snapshot): return snapshot
        case .error(_, let message): throw TransportError.connectionFailed(message)
        default: throw TransportError.unexpectedResponse(response)
        }
    }

    func fetchSnapshot(nodeID: String, scale: Double = 2) async throws -> SnapshotImage? {
        let response = try await send(.fetchSnapshot(nodeID: nodeID, scale: scale))
        switch response {
        case .snapshot(let image): return image
        case .error: return nil
        default: throw TransportError.unexpectedResponse(response)
        }
    }

    @discardableResult
    func setAttribute(nodeID: String, keyPath: String, value: AttributeValue) async throws -> Bool {
        let response = try await send(.setAttribute(nodeID: nodeID, keyPath: keyPath, value: value))
        switch response {
        case .attributeResult(_, _, let success, _): return success
        case .error: return false
        default: throw TransportError.unexpectedResponse(response)
        }
    }

    func ping() async throws {
        let response = try await send(.ping, timeout: 5)
        guard case .pong = response else { throw TransportError.unexpectedResponse(response) }
    }
}
