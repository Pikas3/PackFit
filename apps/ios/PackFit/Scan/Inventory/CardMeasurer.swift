import CoreGraphics
import Foundation
import Vision
import simd

/// Measures every detected object against a credit card in the same photo.
///
/// 1. Vision finds rectangles; the one that fits an ID-1 card through this camera gives the
///    floor's pose (`PlanePose`).
/// 2. Vision's foreground instance segmentation outlines the objects. Those outlines are the
///    objects; Claude only names them. Each detection takes the outline its box overlaps best
///    (Claude's boxes are often offset or clipped). Only when two detections land on one
///    outline (touching objects) is the outline cut by their boxes.
/// 3. `SilhouetteFit` finds the floor-standing box or cylinder whose projection matches each
///    outline. A detection with no outline is not measured: it keeps Claude's estimate.
enum CardMeasurer {
    struct Measured: Sendable {
        var w: Double
        var h: Double
        var d: Double
        var confidence: Double
        var heightReliable: Bool
        var shape: ObjectShape = .box
        /// The fitted solid's outline, normalized 0-1 to the photo.
        var outline: [SIMD2<Double>] = []
    }

    struct Result: Sendable {
        var card: ImageQuad
        /// Same order as the detections passed in; nil where the object could not be measured.
        var measured: [Measured?]
        /// Detections that are the card itself (Claude sometimes lists it).
        var isCard: [Bool]
        /// Camera angle to the card, degrees above the floor (90 = straight down).
        var viewElevation: Double
        /// Where each object really is: the bounds of its segmented outline. Nil where no
        /// outline matched, so Claude's box is all there is.
        var located: [InventoryBox?] = []
    }

    /// Long side of the image Vision and the fit work on. Big enough to see a card's corners.
    static let workingLongSide = 2048.0

    /// Nil when there is no card in the photo.
    nonisolated static func measure(
        image fullImage: CGImage,
        intrinsics fullIntrinsics: CameraIntrinsics,
        boxes: [InventoryBox?],
        shapes: [ObjectShape?] = [],
        cardHint: InventoryBox?
    ) -> Result? {
        let scale = min(1, workingLongSide / Double(max(fullImage.width, fullImage.height)))
        let image = scale < 1 ? (resized(fullImage, scale: scale) ?? fullImage) : fullImage
        let intrinsics = fullIntrinsics.scaled(by: Double(image.width) / Double(fullImage.width))
        let size = SIMD2(Double(image.width), Double(image.height))

        // Vision's corners sit a few pixels off (cards have rounded corners); edges are straight.
        // Refined on the full-resolution photo for sub-pixel corners.
        let up = Double(fullImage.width) / Double(image.width)
        let gray = GrayImage(fullImage)
        let quads = rectangles(in: image).map { quad -> ImageQuad in
            guard let gray, let sharp = CardEdges.refine(ImageQuad(corners: quad.corners.map { $0 * up }), in: gray) else { return quad }
            return ImageQuad(corners: sharp.corners.map { $0 / up })
        }
        guard let pose = PlanePose.bestCard(among: quads, intrinsics: intrinsics, hint: cardHint.map { pixelRect($0, size: size) }) else {
            return nil
        }
        let cardNormalized = ImageQuad(corners: pose.card.corners.map { $0 / size })
        let cardBounds = cardNormalized.bounds
        let labels = instanceLabels(in: image)
        let objects = labels.map { instances(in: $0, card: cardNormalized) } ?? []

        let rects = boxes.map { $0.map { CGRect(x: $0.x, y: $0.y, width: $0.w, height: $0.h) } }
        let isCard = rects.map { rect -> Bool in
            guard let rect else { return false }
            let overlap = rect.intersection(cardBounds)
            return !overlap.isNull && area(overlap) > 0.5 * min(area(rect), area(cardBounds))
        }
        let assigned = match(boxes: rects.enumerated().map { isCard[$0.offset] ? nil : $0.element }, instances: objects)

        // Where each detection's outline comes from: the whole-photo pass, or for objects it
        // left out (it keeps only the most salient things), a second pass on a crop around
        // Claude's box, where that object is the salient one.
        var found = [Found?](repeating: nil, count: boxes.count)
        for i in boxes.indices {
            guard let labels, let j = assigned[i] else { continue }
            let shared = assigned.filter { $0 == j }.count > 1
            // Touching objects segmented as one: each detection keeps its own part.
            let cut = shared ? rects[i].map { $0.insetBy(dx: -$0.width * 0.1, dy: -$0.height * 0.1) } : nil
            found[i] = Found(labels: labels, frame: CGRect(x: 0, y: 0, width: 1, height: 1), object: objects[j], cut: cut)
        }
        for i in boxes.indices where found[i] == nil && !isCard[i] {
            guard let rect = rects[i] else { continue }
            let taken = found.compactMap { $0?.bounds }
            found[i] = segmentCrop(of: image, around: rect, card: cardNormalized, avoiding: taken)
        }

        var measured: [Measured?] = []
        var located: [InventoryBox?] = []
        for i in boxes.indices {
            guard let f = found[i], !f.bounds.isNull, f.bounds.width > 0, f.bounds.height > 0 else {
                measured.append(nil)
                located.append(nil)
                continue
            }
            located.append(InventoryBox(x: f.bounds.minX, y: f.bounds.minY, w: f.bounds.width, h: f.bounds.height))

            let mask = objectMask(f, card: pose.card, imageSize: size)
            let shape = i < shapes.count ? shapes[i] ?? .box : .box
            guard let fit = SilhouetteFit.fit(mask, pose: pose, shape: shape) else {
                measured.append(nil)
                continue
            }
            measured.append(Measured(
                w: round1(fit.long),
                h: round1(fit.height),
                d: round1(fit.short),
                confidence: SilhouetteFit.confidence(fit, mask: mask, pose: pose),
                heightReliable: fit.heightReliable,
                shape: shape,
                outline: fit.outline.map { $0 / size }
            ))
        }
        let elevation = pose.viewElevation(at: [PlanePose.cardLongCm / 2, PlanePose.cardShortCm / 2])
        let fullScale = Double(fullImage.width) / Double(image.width)
        let fullCard = ImageQuad(corners: pose.card.corners.map { $0 * fullScale })
        return Result(card: fullCard, measured: measured, isCard: isCard, viewElevation: elevation, located: located)
    }

    // MARK: Vision

    /// Rectangle candidates in pixels, origin top-left. Loose limits: perspective changes a
    /// card's apparent shape; `PlanePose` decides which one is really a card.
    nonisolated static func rectangles(in image: CGImage) -> [ImageQuad] {
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 12
        request.minimumAspectRatio = 0.25
        request.maximumAspectRatio = 1.0
        request.quadratureTolerance = 35
        request.minimumSize = 0.04
        request.minimumConfidence = 0.5
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        guard (try? handler.perform([request])) != nil, let results = request.results else { return [] }
        let w = Double(image.width), h = Double(image.height)
        return results.map { r in
            ImageQuad(corners: [r.topLeft, r.topRight, r.bottomRight, r.bottomLeft].map {
                SIMD2(Double($0.x) * w, (1 - Double($0.y)) * h)
            })
        }
    }

    /// Per-pixel instance labels (0 = background) at Vision's mask resolution.
    struct LabelMap: Sendable {
        var width: Int
        var height: Int
        var labels: [UInt8]

        func label(atNormalized p: SIMD2<Double>) -> UInt8 {
            let x = min(width - 1, max(0, Int(p.x * Double(width))))
            let y = min(height - 1, max(0, Int(p.y * Double(height))))
            return labels[y * width + x]
        }
    }

    nonisolated static func instanceLabels(in image: CGImage) -> LabelMap? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, orientation: .up)
        guard (try? handler.perform([request])) != nil,
              let buffer = request.results?.first?.instanceMask else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        var labels = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            let row = base.advanced(by: y * stride).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width { labels[y * width + x] = row[x] }
        }
        return LabelMap(width: width, height: height, labels: labels)
    }

    // MARK: Outlines

    /// One segmented object, the card's pixels left out.
    struct Instance: Sendable, Equatable {
        var label: UInt8
        /// Normalized 0-1, origin top-left.
        var bounds: CGRect
        var pixels: Int
    }

    /// Every segmented object except the card itself and specks. `card` is normalized.
    nonisolated static func instances(in map: LabelMap, card: ImageQuad) -> [Instance] {
        var minX = [Int](repeating: .max, count: 256), maxX = [Int](repeating: -1, count: 256)
        var minY = [Int](repeating: .max, count: 256), maxY = [Int](repeating: -1, count: 256)
        var count = [Int](repeating: 0, count: 256), onCard = [Int](repeating: 0, count: 256)
        let size = SIMD2(Double(map.width), Double(map.height))
        let cardBox = card.bounds
        for y in 0..<map.height {
            for x in 0..<map.width {
                let l = Int(map.labels[y * map.width + x])
                guard l != 0 else { continue }
                let p = (SIMD2(Double(x), Double(y)) + 0.5) / size
                if cardBox.contains(CGPoint(x: p.x, y: p.y)) && card.contains(p) {
                    onCard[l] += 1
                    continue
                }
                count[l] += 1
                minX[l] = min(minX[l], x); maxX[l] = max(maxX[l], x)
                minY[l] = min(minY[l], y); maxY[l] = max(maxY[l], y)
            }
        }
        let speck = map.width * map.height / 2000
        return (1..<256).compactMap { l in
            // The card is an object to Vision too; mostly-card outlines are dropped.
            guard count[l] > speck, count[l] > onCard[l] else { return nil }
            return Instance(
                label: UInt8(l),
                bounds: CGRect(
                    x: Double(minX[l]) / size.x, y: Double(minY[l]) / size.y,
                    width: Double(maxX[l] - minX[l] + 1) / size.x, height: Double(maxY[l] - minY[l] + 1) / size.y
                ),
                pixels: count[l]
            )
        }
    }

    /// Which outline each of Claude's boxes names (normalized rects; nil boxes match nothing).
    /// Claude's boxes are rough: often offset or clipped, so the score is how much of the
    /// smaller of the two the other covers, discounted when their sizes differ a lot; a box
    /// that misses every outline takes a nearby one. Greedy best-first, one detection per
    /// outline, then leftovers may share an outline they clearly overlap (touching objects).
    nonisolated static func match(boxes: [CGRect?], instances: [Instance]) -> [Int?] {
        func score(_ box: CGRect, _ object: CGRect) -> Double {
            let overlap = box.intersection(object)
            let small = min(area(box), area(object)), large = max(area(box), area(object))
            guard large > 0 else { return 0 }
            if !overlap.isNull, area(overlap) > 0 {
                return area(overlap) / small * (small / large).squareRoot()
            }
            let gap = hypot(box.midX - object.midX, box.midY - object.midY)
            let reach = hypot(box.width, box.height)
            return gap < reach ? 0.15 * (1 - gap / reach) : 0
        }
        var pairs: [(score: Double, box: Int, object: Int)] = []
        for (i, box) in boxes.enumerated() {
            guard let box else { continue }
            for (j, object) in instances.enumerated() {
                let s = score(box, object.bounds)
                if s >= 0.05 { pairs.append((s, i, j)) }
            }
        }
        // Stable order: by score, then by index, so the same photo always matches the same way.
        pairs.sort { ($0.score, -$0.box, -$0.object) > ($1.score, -$1.box, -$1.object) }
        var result = [Int?](repeating: nil, count: boxes.count)
        var taken = Set<Int>()
        for pair in pairs where result[pair.box] == nil && !taken.contains(pair.object) {
            result[pair.box] = pair.object
            taken.insert(pair.object)
        }
        for pair in pairs where result[pair.box] == nil && pair.score >= 0.3 {
            result[pair.box] = pair.object
        }
        return result
    }

    /// One detection's outline: an instance in a label map that covers `frame` of the photo.
    struct Found: Sendable {
        var labels: LabelMap
        /// The part of the photo the label map covers, normalized (the whole photo, or a crop).
        var frame: CGRect
        /// Bounds normalized to the whole photo.
        var object: Instance
        /// Normalized to the whole photo. Only pixels inside it count.
        var cut: CGRect?

        var bounds: CGRect { cut.map { object.bounds.intersection($0) } ?? object.bounds }
    }

    /// Segments a crop around Claude's box and takes the outline that box names, skipping
    /// outlines already taken by other detections. Everything returned is normalized to the
    /// whole photo; `card` is normalized too.
    nonisolated static func segmentCrop(of image: CGImage, around box: CGRect, card: ImageQuad, avoiding taken: [CGRect]) -> Found? {
        let padX = max(box.width * 0.75, 0.08), padY = max(box.height * 0.75, 0.08)
        let frame = box.insetBy(dx: -padX, dy: -padY).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        let w = Double(image.width), h = Double(image.height)
        let pixels = CGRect(x: frame.minX * w, y: frame.minY * h, width: frame.width * w, height: frame.height * h).integral
        guard pixels.width >= 32, pixels.height >= 32, let crop = image.cropping(to: pixels),
              let labels = instanceLabels(in: crop) else { return nil }
        // What the crop really covers after rounding to whole pixels.
        let covered = CGRect(x: pixels.minX / w, y: pixels.minY / h, width: pixels.width / w, height: pixels.height / h)
        func toCrop(_ p: SIMD2<Double>) -> SIMD2<Double> {
            (p - SIMD2(covered.minX, covered.minY)) / SIMD2(covered.width, covered.height)
        }
        let cropCard = ImageQuad(corners: card.corners.map(toCrop))
        let candidates = instances(in: labels, card: cropCard).map { object -> Instance in
            var o = object
            o.bounds = CGRect(
                x: covered.minX + object.bounds.minX * covered.width,
                y: covered.minY + object.bounds.minY * covered.height,
                width: object.bounds.width * covered.width,
                height: object.bounds.height * covered.height
            )
            return o
        }.filter { object in
            !taken.contains { other in
                let overlap = object.bounds.intersection(other)
                return !overlap.isNull && area(overlap) > 0.5 * area(object.bounds)
            }
        }
        guard let j = match(boxes: [box], instances: candidates).first ?? nil else { return nil }
        return Found(labels: labels, frame: covered, object: candidates[j], cut: nil)
    }

    /// Pixels of one outline (and inside its cut, when there is one), minus the card. `card`
    /// is in pixels of the working image.
    nonisolated static func objectMask(_ found: Found, card: ImageQuad, imageSize: SIMD2<Double>) -> ObjectMask {
        let bounds = found.bounds
        let pixels = CGRect(x: bounds.minX * imageSize.x, y: bounds.minY * imageSize.y,
                            width: bounds.width * imageSize.x, height: bounds.height * imageSize.y)
        let (labels, frame, label, cut) = (found.labels, found.frame, found.object.label, found.cut)
        // Runs off the photo, or off the crop it was segmented in: part of it is not seen.
        let edge = 0.005
        let touches = bounds.minX <= frame.minX + edge || bounds.minY <= frame.minY + edge
            || bounds.maxX >= frame.maxX - edge || bounds.maxY >= frame.maxY - edge
        return ObjectMask(
            region: pixels.insetBy(dx: -pixels.width * 0.15, dy: -pixels.height * 0.15),
            contains: { p in
                let q = p / imageSize
                let point = CGPoint(x: q.x, y: q.y)
                if let cut, !cut.contains(point) { return false }
                guard frame.contains(point) else { return false }
                let local = (q - SIMD2(frame.minX, frame.minY)) / SIMD2(frame.width, frame.height)
                return labels.label(atNormalized: local) == label && !card.contains(p)
            },
            fromSegmentation: cut == nil,
            touchesImageEdge: touches
        )
    }

    // MARK: Helpers

    nonisolated static func pixelRect(_ box: InventoryBox, size: SIMD2<Double>) -> CGRect {
        CGRect(x: box.x * size.x, y: box.y * size.y, width: box.w * size.x, height: box.h * size.y)
    }

    private nonisolated static func resized(_ image: CGImage, scale: Double) -> CGImage? {
        let w = Int((Double(image.width) * scale).rounded()), h = Int((Double(image.height) * scale).rounded())
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    private nonisolated static func area(_ r: CGRect) -> Double { r.isNull ? 0 : r.width * r.height }

    private nonisolated static func round1(_ v: Double) -> Double { (v * 10).rounded() / 10 }
}
