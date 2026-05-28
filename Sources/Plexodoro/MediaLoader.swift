import AVFoundation
import Foundation
import OSLog

private let log = Logger(subsystem: "com.mathewhartley.plexodoro", category: "MediaLoader")

private final class CertDelegate: NSObject, URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}

final class MediaLoader: NSObject, AVAssetResourceLoaderDelegate {
    func resourceLoader(
        _ resourceLoader: AVAssetResourceLoader,
        shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest
    ) -> Bool {
        guard let url = loadingRequest.request.url,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        components.scheme = "https"
        guard let realURL = components.url else { return false }

        log.log("Loading: \(realURL.absoluteString, privacy: .public)")

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        let delegate = CertDelegate()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        session.dataTask(with: realURL) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    log.error("Load failed: \(error.localizedDescription, privacy: .public)")
                    loadingRequest.finishLoading(with: error)
                } else if let data = data, let response = response {
                    if let infoRequest = loadingRequest.contentInformationRequest {
                        infoRequest.contentType = response.mimeType
                        infoRequest.contentLength = response.expectedContentLength
                        infoRequest.isByteRangeAccessSupported = false
                    }
                    loadingRequest.dataRequest?.respond(with: data)
                    loadingRequest.finishLoading()
                    log.log("Loaded \(data.count) bytes")
                } else {
                    loadingRequest.finishLoading(with: URLError(.badServerResponse))
                }
            }
        }.resume()

        return true
    }
}
