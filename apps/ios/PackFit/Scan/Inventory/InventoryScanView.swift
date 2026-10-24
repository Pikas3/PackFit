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
            PhotoWithBoxes(photo: model.photo, entries: model.latestEntries)
                .overlay {
                    if model.phase == .identifying {
                        VStack(spacing: Tokens.Spacing.sm) {
                            ProgressView()
                            Text(Copy.Inventory.identifying)
                                .font(Tokens.TypeScale.callout)
                        }
                        .padding(Tokens.Spacing.md)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Tokens.Radius.md))
                    }
                }
        }
    }

    // MARK: Bottom panel

    @ViewBuilder
    private var panel: some View {
        switch model.phase {
        case .camera:
            VStack(spacing: Tokens.Spacing.sm) {
                Text(Copy.Inventory.hint)
                    .font(Tokens.TypeScale.callout)
                    .multilineTextAlignment(.center)
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
            ScrollView {
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
            Text(Copy.Inventory.estimateNote)
                .font(Tokens.TypeScale.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Button(Copy.Inventory.scanMore) { model.scanAgain() }
                    .buttonStyle(.bordered)
                Spacer()
                Button(Copy.Inventory.add(model.includedCount)) {
                    for item in model.itemsToAdd { itemsStore.append(item) }
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
                    Text(String(format: "%@ · ~%.0f×%.0f×%.0f cm · %.2f kg",
                                entry.item.category.rawValue, entry.item.w, entry.item.h, entry.item.d, entry.item.kg))
                        .font(Tokens.TypeScale.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        ConfidenceBadge(confidence: entry.item.confidence)
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
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    if let box = entry.box {
                        let rect = CGRect(
                            x: fitted.minX + box.x * fitted.width,
                            y: fitted.minY + box.y * fitted.height,
                            width: box.w * fitted.width,
                            height: box.h * fitted.height
                        )
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(entry.included ? Tokens.Color.brand : .gray, lineWidth: 2)
                            .frame(width: rect.width, height: rect.height)
                            .overlay(alignment: .topLeading) {
                                Text("\(index + 1) \(entry.item.name)")
                                    .font(Tokens.TypeScale.caption)
                                    .lineLimit(1)
                                    .padding(.horizontal, 4)
                                    .background(entry.included ? Tokens.Color.brand : .gray)
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
