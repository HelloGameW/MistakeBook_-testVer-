#if canImport(CoreGraphics) && canImport(ImageIO)
import CoreGraphics
import Foundation
import ImageIO
import Contracts

/// Pixel heuristic for grading marks: red-dominant strokes (red pen "\" marks,
/// circled answers and corrections) on an otherwise non-red page.
public struct GradingMarkHeuristicsDetector: GradingMarkDetectionService {
    public init() {}

    public func detectGradingMarks(payload: ImagePayload, focus: NormalizedRect?) async -> Bool {
        guard let source = CGImageSourceCreateWithData(payload.bytes as CFData, nil),
              var image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return false }
        if let focus {
            let scale = max(1, max(image.width, image.height))
            let rect = CGRect(x: focus.x * Double(image.width), y: focus.y * Double(image.height),
                              width: focus.width * Double(image.width), height: focus.height * Double(image.height))
            if let cropped = image.cropping(to: rect.integral) { image = cropped }
        }
        guard let downsampled = Self.downsample(image, maxDimension: 256),
              let ratio = Self.redPixelRatio(downsampled) else { return false }
        return ratio >= 0.003
    }

    private static func downsample(_ image: CGImage, maxDimension: Int) -> CGImage? {
        guard max(image.width, image.height) > maxDimension else { return image }
        let scale = Double(maxDimension) / Double(max(image.width, image.height))
        let width = max(1, Int(Double(image.width) * scale))
        let height = max(1, Int(Double(image.height) * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .low
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }

    private static func redPixelRatio(_ image: CGImage) -> Double? {
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let data = context.data else { return nil }
        let buffer = data.bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
        var redPixels = 0
        let total = image.width * image.height
        for pixel in 0..<total {
            let r = Int(buffer[pixel * 4]), g = Int(buffer[pixel * 4 + 1]), b = Int(buffer[pixel * 4 + 2])
            if r > 90, r > g * 3 / 2, r > b * 3 / 2, r - max(g, b) > 30 { redPixels += 1 }
        }
        return Double(redPixels) / Double(max(1, total))
    }
}
#else
import Foundation
import Contracts

/// Platforms without image support never report grading marks.
public struct GradingMarkHeuristicsDetector: GradingMarkDetectionService {
    public init() {}
    public func detectGradingMarks(payload: ImagePayload, focus: NormalizedRect?) async -> Bool { false }
}
#endif
