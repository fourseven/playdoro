import Foundation
import CryptoKit
import Logging

private let log = Logger(label: AppIdentity.key("cert"))

/// URLSession delegate that handles Plex LAN servers' self-signed certificates.
///
/// Behaviour:
/// - **Public hosts** (`plex.tv`, the relay, `*.plex.direct`, any non-private
///   address) get normal system certificate validation — security is never
///   weakened there.
/// - **Private/LAN hosts** (RFC1918, loopback, link-local, `.local`) use
///   trust-on-first-use (TOFU): on the first connection the SHA-256 of the
///   server's public key is recorded and pinned. Subsequent connections must
///   present the same key, which defeats MITM after the first pairing. If the
///   server's key changes (e.g. a regenerated cert), the pin mismatches and the
///   connection is rejected — disconnect and reconnect to re-pair.
final class CertDelegate: NSObject, URLSessionDelegate {
    private static let pinPrefix = "certPin."

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        let host = challenge.protectionSpace.host

        // Only relax validation for clearly-private LAN hosts. Everything else
        // is validated normally by the system against the system CA store.
        guard Self.isPrivate(host: host) else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // LAN host with a (likely self-signed) cert — apply TOFU.
        guard let keyHash = Self.publicKeyHash(for: trust) else {
            log.warning("Could not extract server public key for \(host); rejecting")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        let pinKey = Self.pinDefaultsKey(for: host)
        let stored = UserDefaults.standard.data(forKey: pinKey)

        if stored == nil {
            // First contact with this host — auto-accept and pin the key.
            UserDefaults.standard.set(keyHash, forKey: pinKey)
            log.info("Pinning server cert for \(host) (TOFU)")
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else if stored == keyHash {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            log.error("Cert pin mismatch for \(host) — possible MITM or server key rotation. Rejecting (disconnect + reconnect to re-pair).")
            completionHandler(.cancelAuthenticationChallenge, nil)
        }
    }

    // MARK: - Pin management

    /// Remove every stored cert pin so the next connection re-pins (TOFU again).
    static func clearAllStoredPins() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(pinPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Internals

    private static func pinDefaultsKey(for host: String) -> String {
        "\(pinPrefix)\(host)"
    }

    /// SHA-256 of the leaf certificate's public key. Stable across cert
    /// re-signings as long as the server keeps the same key pair.
    private static func publicKeyHash(for trust: SecTrust) -> Data? {
        guard let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
              let leaf = chain.first,
              let key = SecCertificateCopyKey(leaf),
              let keyData = SecKeyCopyExternalRepresentation(key, nil) as Data? else {
            return nil
        }
        return Data(SHA256.hash(data: keyData))
    }

    /// True for loopback, link-local, RFC1918, and `.local` mDNS hosts — i.e.
    /// the addresses a self-signed Plex LAN server would use.
    private static func isPrivate(host: String) -> Bool {
        let h = host.lowercased()
        if h == "localhost" || h.hasSuffix(".local") { return true }
        // IPv6 loopback / link-local
        if h == "::1" || h.hasPrefix("fe80:") { return true }
        // IPv4 dotted-quad checks
        let parts = h.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        let (a, b) = (parts[0], parts[1])
        if a == 127 { return true }                          // loopback
        if a == 169 && b == 254 { return true }              // link-local
        if a == 10 { return true }                           // RFC1918
        if a == 192 && b == 168 { return true }              // RFC1918
        if a == 172 && (16...31).contains(b) { return true } // RFC1918
        return false
    }
}
