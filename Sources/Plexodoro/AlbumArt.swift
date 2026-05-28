import SwiftUI

private let session: URLSession = {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 10
    let delegate = CertDelegate()
    return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
}()

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

struct AlbumArt: View {
    let url: URL?
    @State private var imageData: Data?

    var body: some View {
        Group {
            if let data = imageData, let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if url != nil {
                Color(nsColor: .controlBackgroundColor)
                    .overlay {
                        ProgressView()
                            .scaleEffect(0.5)
                    }
            } else {
                Color(nsColor: .controlBackgroundColor)
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.title)
                            .foregroundColor(.secondary)
                    }
            }
        }
        .task {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let url = url, imageData == nil else { return }
        imageData = try? await session.data(from: url).0
    }
}
