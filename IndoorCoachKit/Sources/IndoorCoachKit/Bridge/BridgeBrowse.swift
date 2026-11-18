import Foundation
import Network

/// Client-side network helpers: Bonjour browsing and channel creation.
enum BridgeBrowse {
    private static let queue = DispatchQueue(label: "app.indoorcoach.bridge.client")

    static func channel(to endpoint: NWEndpoint, psk: Data, identity: String) -> BridgeChannel {
        let connection = NWConnection(to: endpoint, using: BridgeCrypto.parameters(psk: psk, identity: identity))
        return BridgeChannel(connection: connection, queue: queue)
    }

    private final class Collector: @unchecked Sendable {
        private let lock = NSLock()
        private var found: [String: DiscoveredBridge] = [:]
        func set(_ results: Set<NWBrowser.Result>) {
            var next: [String: DiscoveredBridge] = [:]
            for result in results {
                if case .service(let name, _, _, _) = result.endpoint {
                    next[name] = DiscoveredBridge(name: name, endpoint: result.endpoint)
                }
            }
            lock.withLock { found = next }
        }
        var all: [DiscoveredBridge] { lock.withLock { found.values.sorted { $0.name < $1.name } } }
    }

    static func discover(type: String, timeout: Duration) async -> [DiscoveredBridge] {
        let browser = NWBrowser(for: .bonjour(type: type, domain: nil), using: .tcp)
        let collector = Collector()
        browser.browseResultsChangedHandler = { results, _ in collector.set(results) }
        browser.start(queue: queue)
        try? await Task.sleep(for: timeout)
        browser.cancel()
        let result = collector.all
        Log.notice(.bridge, "discovered \(result.count) bridges")
        return result
    }
}
