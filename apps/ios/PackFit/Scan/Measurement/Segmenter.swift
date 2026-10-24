import CoreGraphics
import CoreVideo
import Foundation
import Vision

/// A camera image already turned upright (portrait), ready for Vision.
struct UprightImage: @unchecked Sendable {
    let cgImage: CGImage
}

/// Separates foreground objects in the camera image with Vision's subject-lifting model.
/// The image gives sharp object outlines that the 256×192 depth map can't, which is what
/// keeps thin items and box edges tight.
enum Segmenter {
    static func labels(for image: UprightImage) -> InstanceLabels? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image.cgImage, orientation: .up)
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let observation = request.results?.first else { return nil }
        let buffer = observation.instanceMask
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent8 else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let w = CVPixelBufferGetWidth(buffer), h = CVPixelBufferGetHeight(buffer)
        let row = CVPixelBufferGetBytesPerRow(buffer)
        var labels = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            let p = base.advanced(by: y * row).assumingMemoryBound(to: UInt8.self)
            for x in 0..<w { labels[y * w + x] = p[x] }
        }
        return InstanceLabels(width: w, height: h, labels: labels)
    }
}
