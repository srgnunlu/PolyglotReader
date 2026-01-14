import Foundation
import Combine
import Network

// MARK: - Connection Type
/// Represents the type of network connection available
enum ConnectionType: String {
    case wifi = "WiFi"
    case cellular = "Cellular"
    case ethernet = "Ethernet"
    case unknown = "Unknown"
    case none = "None"
}

// MARK: - Network Monitor
/// Singleton service for monitoring network connectivity using NWPathMonitor
/// Provides reactive connectivity status updates via Combine publishers
@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    // MARK: - Published Properties

    /// Whether the device is currently connected to the internet
    @Published private(set) var isConnected: Bool = true

    /// The type of network connection (wifi/cellular/none)
    @Published private(set) var connectionType: ConnectionType = .unknown

    /// Whether the connection is expensive (cellular data)
    @Published private(set) var isExpensive: Bool = false

    /// Whether the connection is constrained (low data mode)
    @Published private(set) var isConstrained: Bool = false

    // MARK: - Private Properties

    private let monitor: NWPathMonitor
    private let queue: DispatchQueue
    private var previouslyConnected: Bool = true

    // MARK: - Notifications

    /// Notification posted when network becomes available
    static let networkDidBecomeAvailable = Notification.Name("NetworkMonitor.networkDidBecomeAvailable")

    /// Notification posted when network becomes unavailable
    static let networkDidBecomeUnavailable = Notification.Name("NetworkMonitor.networkDidBecomeUnavailable")

    // MARK: - Initialization

    private init() {
        monitor = NWPathMonitor()
        queue = DispatchQueue(label: "com.polyglotreader.networkmonitor", qos: .utility)

        setupMonitor()
        startMonitoring()

        #if DEBUG
        MemoryDebugger.shared.logInit(self)
        #endif
    }

    deinit {
        // Call cancel directly on monitor (avoids @MainActor isolation issue)
        monitor.cancel()
        #if DEBUG
        Task { @MainActor in
            MemoryDebugger.shared.logDeinit(self)
        }
        #endif
    }

    // MARK: - Setup

    private func setupMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                self?.handlePathUpdate(path)
            }
        }
    }

    private func handlePathUpdate(_ path: NWPath) {
        let newIsConnected = path.status == .satisfied
        let wasConnected = previouslyConnected

        // Update connection status
        isConnected = newIsConnected
        isExpensive = path.isExpensive
        isConstrained = path.isConstrained

        // Determine connection type
        connectionType = determineConnectionType(from: path)

        // Log status change
        if newIsConnected != wasConnected {
            if newIsConnected {
                logInfo("NetworkMonitor", "Network connection restored", details: connectionType.rawValue)
                NotificationCenter.default.post(name: Self.networkDidBecomeAvailable, object: nil)
            } else {
                logWarning("NetworkMonitor", "Network connection lost")
                NotificationCenter.default.post(name: Self.networkDidBecomeUnavailable, object: nil)
            }
        }

        previouslyConnected = newIsConnected
    }

    private func determineConnectionType(from path: NWPath) -> ConnectionType {
        guard path.status == .satisfied else {
            return .none
        }

        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .ethernet
        } else {
            return .unknown
        }
    }

    // MARK: - Public Methods

    /// Start monitoring network status
    func startMonitoring() {
        monitor.start(queue: queue)
        logDebug("NetworkMonitor", "Started network monitoring")
    }

    /// Stop monitoring network status
    func stopMonitoring() {
        monitor.cancel()
        logDebug("NetworkMonitor", "Stopped network monitoring")
    }

    /// Check if a specific interface type is available
    /// - Parameter interfaceType: The interface type to check
    /// - Returns: Whether the interface is available
    func isInterfaceAvailable(_ interfaceType: NWInterface.InterfaceType) -> Bool {
        let path = monitor.currentPath
        return path.usesInterfaceType(interfaceType)
    }

    /// Human-readable description of current network status
    var statusDescription: String {
        if isConnected {
            var description = connectionType.rawValue
            if isExpensive {
                description += " (Sınırlı veri)"
            }
            if isConstrained {
                description += " (Düşük veri modu)"
            }
            return description
        } else {
            return "Çevrimdışı"
        }
    }
}
