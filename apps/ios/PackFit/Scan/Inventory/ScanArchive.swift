import Foundation

/// Debug builds keep each inventory photo with what the app made of it, in Documents/Scans
/// (Files app: On My iPhone › PackFit), so a real scan can be replayed on the Mac.
enum ScanArchive {
    struct Record: Encodable, Sendable {
        struct Measured: Encodable, Sendable {
            var w: Double
            var h: Double
            var d: Double
            var confidence: Double
            var shape: String
            var outline: [[Double]]
        }

        var imageWidth: Int
        var imageHeight: Int
        var fieldOfView: Double
        var focalLength35mm: Double?
        var fx: Double?
        var response: ScanInventoryResponse
        /// Card corners in full-resolution pixels; nil when no card was found.
        var card: [[Double]]?
        var measured: [Measured?]
        var located: [InventoryBox?]
    }

    static func record(shot: InventoryCamera.Shot, response: ScanInventoryResponse, result: CardMeasurer.Result?) -> Record {
        Record(
            imageWidth: shot.image.width,
            imageHeight: shot.image.height,
            fieldOfView: shot.fieldOfView,
            focalLength35mm: shot.focalLength35mm,
            fx: shot.intrinsics?.fx,
            response: response,
            card: result?.card.corners.map { [$0.x, $0.y] },
            measured: result?.measured.map { m in
                m.map { Record.Measured(w: $0.w, h: $0.h, d: $0.d, confidence: $0.confidence, shape: $0.shape.rawValue,
                                        outline: $0.outline.map { [$0.x, $0.y] }) }
            } ?? [],
            located: result?.located ?? []
        )
    }

    @concurrent
    nonisolated static func save(jpeg: Data, record: Record) async {
        #if DEBUG
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let folder = documents.appending(path: "Scans/\(formatter.string(from: Date()))")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try jpeg.write(to: folder.appending(path: "photo.jpg"))
            try encoder.encode(record).write(to: folder.appending(path: "scan.json"))
        } catch {
            // Debug aid only; a failed save never affects the scan.
        }
        #endif
    }
}
