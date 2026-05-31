import Foundation

public enum ProtocolConstants {
    /// Human-readable release version.
    public static let version = "0.1.1"
    /// Wire protocol version; bump on incompatible message changes.
    public static let protocolVersion = 1

    /// Loopback host the in-app server binds to.
    public static let loopbackHost = "127.0.0.1"

    /// Default TCP port the server attempts first, then increments on conflict.
    public static let defaultPort: UInt16 = 50_067
    /// How many sequential ports to try before giving up.
    public static let portScanCount = 16

    /// Bonjour service type used for zero-config discovery on the local machine
    /// (works for the iOS Simulator and macOS hosts sharing the network stack).
    public static let bonjourServiceType = "_treescope._tcp"

    /// Magic prefix on every wire frame, for stream sanity checks.
    public static let frameMagic: UInt32 = 0x5453_4350 // "TSCP"

    /// Hard cap on a single frame to avoid runaway allocations from junk data.
    public static let maxFrameBytes = 64 * 1024 * 1024
}
