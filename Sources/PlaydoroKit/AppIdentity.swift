import Foundation

/// Single home for the product's identity. Rename the app by changing the
/// values here — nothing else in the codebase hard-codes the name, namespace,
/// or version.
enum AppIdentity {
    /// Display name, also sent to Plex as the client name in request headers
    /// (Product / Device / Model / Device-Name).
    static let name = "Playdoro"

    /// Version reported to Plex in the timeline/API headers.
    static let version = "1.0"

    /// Reverse-DNS namespace prefixing logger labels and persistence keys.
    static let reverseDNS = "com.playdoro"

    /// Scoped key for a UserDefaults key, cache subdirectory, logger label, etc.
    static func key(_ name: String) -> String {
        "\(reverseDNS).\(name)"
    }

    /// URL-safe filename for the on-disk audio log inside the temp directory.
    static let audioLogFileName = "\(name.lowercased())_audio_player.log"
}