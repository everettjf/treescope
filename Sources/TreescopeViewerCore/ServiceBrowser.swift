import Foundation
import Combine
import Network
import TreescopeProtocol

public struct DiscoveredService: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let endpoint: NWEndpoint
    public init(name: String, endpoint: NWEndpoint) {
        self.name = name
        self.endpoint = endpoint
        self.id = name
    }
}

/// Browses the local network (Bonjour) for Treescope servers. The viewer can
/// also connect manually by host/port, so discovery is a convenience.
@MainActor
public final class ServiceBrowser: ObservableObject {
    @Published public private(set) var services: [DiscoveredService] = []
    @Published public private(set) var isBrowsing = false

    private var browser: NWBrowser?

    public init() {}

    public func start() {
        guard browser == nil else { return }
        let params = NWParameters()
        params.includePeerToPeer = false
        let descriptor = NWBrowser.Descriptor.bonjour(type: ProtocolConstants.bonjourServiceType, domain: nil)
        let browser = NWBrowser(for: descriptor, using: params)

        browser.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready: self?.isBrowsing = true
                case .failed, .cancelled: self?.isBrowsing = false
                default: break
                }
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let discovered = results.compactMap { result -> DiscoveredService? in
                if case let .service(name, _, _, _) = result.endpoint {
                    return DiscoveredService(name: name, endpoint: result.endpoint)
                }
                return nil
            }
            DispatchQueue.main.async {
                self?.services = discovered.sorted { $0.name < $1.name }
            }
        }

        self.browser = browser
        browser.start(queue: .main)
    }

    public func stop() {
        browser?.cancel()
        browser = nil
        isBrowsing = false
        services = []
    }
}
