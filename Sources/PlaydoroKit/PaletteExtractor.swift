import SwiftUI
import CoreImage
import Logging

#if canImport(UIKit)
import UIKit
typealias PlatformColor = UIColor
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformColor = NSColor
typealias PlatformImage = NSImage
#endif

private let log = Logger(label: AppIdentity.key("palette"))

struct AlbumPalette: Equatable {
    let primary: Color
    let secondary: Color
}

enum PaletteExtractor {
    static func extract(from data: Data) async -> AlbumPalette? {
        let task = Task.detached(priority: .userInitiated) { () -> AlbumPalette? in
            guard let cgImage = cgImage(from: data) else { return nil }
            let ciImage = CIImage(cgImage: cgImage)

            let targetSize: CGFloat = 64
            let scaleX = targetSize / ciImage.extent.width
            let scaleY = targetSize / ciImage.extent.height
            let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
            let extent = scaled.extent
            let extentVector = CIVector(cgRect: extent)
            let context = CIContext(options: [.workingColorSpace: kCFNull as Any])

            guard let avgFilter = CIFilter(name: "CIAreaAverage",
                                            parameters: [kCIInputImageKey: scaled, kCIInputExtentKey: extentVector]),
                  let avgOutput = avgFilter.outputImage else { return nil }
            var avgBitmap = [UInt8](repeating: 0, count: 4)
            context.render(avgOutput, toBitmap: &avgBitmap, rowBytes: 4,
                           bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                           format: .RGBA8, colorSpace: nil)

            guard let maxFilter = CIFilter(name: "CIAreaMaximum",
                                            parameters: [kCIInputImageKey: scaled, kCIInputExtentKey: extentVector]),
                  let maxOutput = maxFilter.outputImage else { return nil }
            var maxBitmap = [UInt8](repeating: 0, count: 4)
            context.render(maxOutput, toBitmap: &maxBitmap, rowBytes: 4,
                           bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                           format: .RGBA8, colorSpace: nil)

            let primary = boostColor(red: avgBitmap[0], green: avgBitmap[1], blue: avgBitmap[2])
            let secondary = boostColor(red: maxBitmap[0], green: maxBitmap[1], blue: maxBitmap[2])

            return AlbumPalette(primary: Color(primary), secondary: Color(secondary))
        }
        return await task.value
    }

    private static func boostColor(red: UInt8, green: UInt8, blue: UInt8) -> PlatformColor {
        let r = CGFloat(red) / 255
        let g = CGFloat(green) / 255
        let b = CGFloat(blue) / 255
        var hue: CGFloat = 0, sat: CGFloat = 0, bright: CGFloat = 0, alpha: CGFloat = 0
        PlatformColor(red: r, green: g, blue: b, alpha: 1)
            .getHue(&hue, saturation: &sat, brightness: &bright, alpha: &alpha)

        let boostedSat = CGFloat(min(0.85, max(0.55, Double(sat) * 1.4)))
        let boostedBright = CGFloat(min(1.0, max(0.55, Double(bright) * 1.05)))
        #if canImport(UIKit)
        return PlatformColor(hue: hue, saturation: boostedSat, brightness: boostedBright, alpha: 1)
        #else
        return PlatformColor(calibratedHue: hue, saturation: boostedSat, brightness: boostedBright, alpha: 1)
        #endif
    }

    private static func cgImage(from data: Data) -> CGImage? {
        guard let image = PlatformImage(data: data) else { return nil }
        #if canImport(UIKit)
        return image.cgImage
        #else
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #endif
    }
}
