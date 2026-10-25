import AVFoundation
import SwiftUI

/// Photo inventory: snap the pile, Claude names every object in frame, tick what to pack.
struct InventoryScanView: View {
    @Environment(ItemsStore.self) private var itemsStore
    @Binding var path: [Route]
    @State private var model: InventoryScanModel
    @State private var editing: Item?

    init(path: Binding<[Route]>, client: any APIClient) {
        _path = path
        _model = State(initialValue: InventoryScanModel(client: client))
    }

    var body: some View {
        VStack(spacing: 0) {
            if model.isSampleData {
                Label(Copy.Inventory.sampleData, systemImage: "exclamationmark.triangle.fill")
                    .font(Tokens.TypeScale.caption)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Tokens.Spacing.md)
                    .padding(.vertical, Tokens.Spacing.sm)
                    .background(Color.yellow)
                    .accessibilityAddTraits(.isStaticText)
            }
            stage
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            panel
                .padding(Tokens.Spacing.md)
                .background(.bar)
        }
        .loadingModal(
            isPresented: model.phase == .identifying,
            title: Copy.Loading.identifyingTitle,
            message: Copy.Loading.inventoryWait
        )
        .navigationTitle(Copy.Inventory.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.startCamera() }
        .onDisappear { model.stopCamera() }
        .sheet(item: $editing) { item in
            ItemDetailView(item: item, flags: []) { updated in
                model.update(updated)
                editing = nil
            }
        }
    }

    // MARK: Camera or frozen photo

    @ViewBuilder
    private var stage: some View {
        if model.phase == .camera {
            ZStack {
                if model.cameraAvailable {
                    CameraPreview(session: model.camera.session)
                    // Preview and video frames are both 3:4 portrait, aspect-fit.
                    QuadOverlay(quad: model.camera.liveCard, aspect: 3.0 / 4.0, color: .green)
                } else {
                    Color.black
                    Text(Copy.Inventory.simulator)
                        .font(Tokens.TypeScale.callout)
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding()
                }
                if let error = model.cameraError {
                    Text(error)
                        .font(Tokens.TypeScale.callout)
                        .padding(Tokens.Spacing.sm)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Tokens.Radius.sm))
                }
            }
        } else {
            PhotoWithBoxes(photo: model.photo, entries: model.phase == .noCard ? [] : model.latestEntries, card: model.card)
        }
    }

    // MARK: Bottom panel

    @ViewBuilder
    private var panel: some View {
        switch model.phase {
        case .camera:
            VStack(spacing: Tokens.Spacing.sm) {
                if model.cameraAvailable, model.camera.liveCard != nil {
                    Label(Copy.Inventory.cardSeen, systemImage: "checkmark.circle.fill")
                        .font(Tokens.TypeScale.callout)
                        .foregroundStyle(.green)
                } else {
                    Text(Copy.Inventory.hint)
                        .font(Tokens.TypeScale.callout)
                        .multilineTextAlignment(.center)
                }
                Button {
                    Task { await model.captureAndIdentify() }
                } label: {
                    Label(Copy.Inventory.capture, systemImage: "camera.viewfinder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Tokens.Color.brand)
                .controlSize(.large)
                if !model.entries.isEmpty {
                    Button(Copy.Inventory.review(model.entries.count)) {
                        model.showResults()
                    }
                }
            }
        case .identifying:
            Text(Copy.Inventory.privacy)
                .font(Tokens.TypeScale.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        case .noCard:
            VStack(spacing: Tokens.Spacing.sm) {
                Label(Copy.Inventory.noCard, systemImage: "creditcard")
                    .font(Tokens.TypeScale.callout)
                Button(Copy.Inventory.tryAgain) { model.scanAgain() }
                    .buttonStyle(.borderedProminent)
                    .tint(Tokens.Color.brand)
                Button(Copy.Inventory.useEstimates) { model.useEstimates() }
            }
        case .failed(let message):
            VStack(spacing: Tokens.Spacing.sm) {
                Text(message)
                    .font(Tokens.TypeScale.callout)
                    .multilineTextAlignment(.center)
                Button(Copy.Inventory.tryAgain) { model.scanAgain() }
                    .buttonStyle(.borderedProminent)
                    .tint(Tokens.Color.brand)
                if !model.entries.isEmpty {
                    Button(Copy.Inventory.review(model.entries.count)) { model.showResults() }
                }
            }
        case .results:
            results
        }
    }

    private var results: some View {
        VStack(spacing: Tokens.Spacing.sm) {
            HStack {
                Text(Copy.Inventory.found(model.entries.count))
                    .font(Tokens.TypeScale.title)
                Spacer()
            }
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: Tokens.Spacing.sm) {
                    ForEach(model.entries) { entry in
                        InventoryRow(
                            entry: entry,
                            onToggle: { model.toggle(entry.id) },
                            onEdit: { editing = entry.item },
                            onRemove: { model.remove(entry.id) }
                        )
                    }
                }
            }
            .frame(maxHeight: 300)
            Text(model.entries.contains(where: \.measuredWithCard) ? Copy.Inventory.measuredNote : Copy.Inventory.estimateNote)
                .font(Tokens.TypeScale.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if model.heightsGuessed {
                Text(Copy.Inventory.steepNote)
                    .font(Tokens.TypeScale.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Button(Copy.Inventory.scanMore) { model.scanAgain() }
                    .buttonStyle(.bordered)
                Spacer()
                Button(Copy.Inventory.add(model.includedCount)) {
                    for item in model.itemsToAdd { itemsStore.append(item) }
                    itemsStore.shapes.merge(model.shapesToAdd) { _, new in new }
                    if path.last == .inventoryScan { path.removeLast() }
                    if path.last != .itemList { path.append(.itemList) }
                }
                .buttonStyle(.borderedProminent)
                .tint(Tokens.Color.brand)
                .disabled(model.includedCount == 0)
            }
        }
    }
}

private struct InventoryRow: View {
    let entry: InventoryEntry
    let onToggle: () -> Void
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: Tokens.Spacing.md) {
            Button(action: onToggle) {
                Image(systemName: entry.included ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(entry.included ? Tokens.Color.brand : .secondary)
            }
            .accessibilityLabel(entry.included ? Copy.Inventory.included : Copy.Inventory.excluded)

            thumbnail
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.sm))

            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                    Text(entry.item.name)
                        .font(Tokens.TypeScale.body)
                        .foregroundStyle(.primary)
                    Text(String(format: "%@ · %@%.1f×%.1f×%.1f cm · %.2f kg",
                                entry.item.category.rawValue, entry.measuredWithCard ? "" : "~",
                                entry.item.w, entry.item.h, entry.item.d, entry.item.kg))
                        .font(Tokens.TypeScale.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        MeasurementMethodBadge(method: entry.item.measurement?.method)
                        ConfidenceBadge(confidence: entry.item.measurement?.confidence ?? entry.item.confidence)
                        if entry.likelyDuplicate {
                            Text(Copy.Inventory.duplicate)
                                .font(Tokens.TypeScale.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Copy.Items.delete)
        }
        .opacity(entry.included ? 1 : 0.6)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = entry.thumbnail {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
        } else {
            Tokens.Color.brandSecondary.opacity(0.35)
                .overlay {
                    Text(String(entry.item.category.rawValue.prefix(1)).uppercased())
                        .font(Tokens.TypeScale.title)
                }
        }
    }
}

/// The captured photo, aspect-fit, with a numbered outline per detected object.
private struct PhotoWithBoxes: View {
    let photo: CGImage?
    let entries: [InventoryEntry]
    var card: ImageQuad?

    var body: some View {
        GeometryReader { geo in
            let aspect = photo.map { CGFloat($0.width) / CGFloat($0.height) } ?? 3.0 / 4.0
            let fitted = Self.fit(aspect: aspect, in: geo.size)
            ZStack(alignment: .topLeading) {
                Color.black
                if let photo {
                    Image(decorative: photo, scale: 1)
                        .resizable()
                        .frame(width: fitted.width, height: fitted.height)
                        .offset(x: fitted.minX, y: fitted.minY)
                }
                if let card {
                    QuadOverlay(quad: card, aspect: aspect, color: .yellow)
                }
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    let color = entry.included ? Tokens.Color.brand : Color.gray
                    // What was measured: the fitted box or cylinder, traced over the object.
                    if let outline = entry.outline, outline.count >= 3 {
                        Path { path in
                            path.addLines(outline.map {
                                CGPoint(x: fitted.minX + $0.x * fitted.width, y: fitted.minY + $0.y * fitted.height)
                            })
                            path.closeSubpath()
                        }
                        .fill(color.opacity(0.18))
                        .overlay {
                            Path { path in
                                path.addLines(outline.map {
                                    CGPoint(x: fitted.minX + $0.x * fitted.width, y: fitted.minY + $0.y * fitted.height)
                                })
                                path.closeSubpath()
                            }
                            .stroke(color, lineWidth: 2)
                        }
                        .allowsHitTesting(false)
                    }
                    if let box = entry.box {
                        let rect = CGRect(
                            x: fitted.minX + box.x * fitted.width,
                            y: fitted.minY + box.y * fitted.height,
                            width: box.w * fitted.width,
                            height: box.h * fitted.height
                        )
                        // Measured objects show their outline; the box only anchors the label.
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(color, style: StrokeStyle(lineWidth: entry.outline == nil ? 2 : 1, dash: entry.outline == nil ? [] : [4, 4]))
                            .frame(width: rect.width, height: rect.height)
                            .overlay(alignment: .topLeading) {
                                Text("\(index + 1) \(entry.item.name)")
                                    .font(Tokens.TypeScale.caption)
                                    .lineLimit(1)
                                    .padding(.horizontal, 4)
                                    .background(color)
                                    .foregroundStyle(.white)
                            }
                            .offset(x: rect.minX, y: rect.minY)
                    }
                }
            }
        }
    }

    static func fit(aspect: CGFloat, in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        if size.width / size.height > aspect {
            let w = size.height * aspect
            return CGRect(x: (size.width - w) / 2, y: 0, width: w, height: size.height)
        }
        let h = size.width / aspect
        return CGRect(x: 0, y: (size.height - h) / 2, width: size.width, height: h)
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

/// Outline of a quad given in normalized image coordinates, over an aspect-fit image.
private struct QuadOverlay: View {
    let quad: ImageQuad?
    let aspect: CGFloat
    let color: Color

    var body: some View {
        GeometryReader { geo in
            if let quad, quad.corners.count == 4 {
                let fitted = PhotoWithBoxes.fit(aspect: aspect, in: geo.size)
                Path { path in
                    let points = quad.corners.map {
                        CGPoint(x: fitted.minX + $0.x * fitted.width, y: fitted.minY + $0.y * fitted.height)
                    }
                    path.addLines(points)
                    path.closeSubpath()
                }
                .stroke(color, lineWidth: 3)
            }
        }
        .allowsHitTesting(false)
    }
}
