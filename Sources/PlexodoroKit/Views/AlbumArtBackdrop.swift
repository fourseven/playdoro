import SwiftUI
import Logging

private let log = Logger(label: "com.plexodoro.backdrop")

private let backdropSession: URLSession = {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 10
    config.requestCachePolicy = .returnCacheDataElseLoad
    return URLSession(configuration: config, delegate: CertDelegate(), delegateQueue: nil)
}()

/// Full-bleed, blurred album-art backdrop with a darkening overlay.
/// Used as the immersive background for active session and idle screens.
/// Reports the extracted two-color palette via `onPalette` so callers can
/// theme accents, gradients, and tints to match the art.
struct AlbumArtBackdrop: View {
    let url: URL?
    var blurRadius: CGFloat = 60
    var overlayOpacity: Double = 0.55
    var onPalette: ((AlbumPalette?) -> Void)? = nil

    @State private var imageData: Data?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.background

                if let data = imageData {
                    #if os(iOS)
                    if let image = UIImage(data: data) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width * 1.2, height: geo.size.height * 1.2)
                            .blur(radius: blurRadius)
                            .opacity(0.7)
                            .clipped()
                    }
                    #elseif os(macOS)
                    if let image = NSImage(data: data) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width * 1.2, height: geo.size.height * 1.2)
                            .blur(radius: blurRadius)
                            .opacity(0.7)
                            .clipped()
                    }
                    #endif
                }

                LinearGradient(
                    colors: [
                        Theme.background.opacity(overlayOpacity),
                        Theme.background.opacity(overlayOpacity + 0.2),
                        Theme.background.opacity(0.9)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
        }
        .ignoresSafeArea()
        .task(id: url) {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let url else {
            imageData = nil
            await reportPalette(nil)
            return
        }
        if let cached = URLCache.shared.cachedResponse(for: URLRequest(url: url))?.data {
            imageData = cached
            await reportPalette(cached)
            return
        }
        do {
            let (data, response) = try await backdropSession.data(from: url)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                imageData = data
                await reportPalette(data)
            }
        } catch {
            log.debug("Backdrop fetch failed: \(error.localizedDescription)")
        }
    }

    private func reportPalette(_ data: Data?) async {
        guard let data else {
            onPalette?(nil)
            return
        }
        let palette = await PaletteExtractor.extract(from: data)
        onPalette?(palette)
    }
}
