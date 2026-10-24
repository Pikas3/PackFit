import SwiftUI

struct ScanView: View {
    @Environment(ItemsStore.self) private var itemsStore
    @Environment(DeviceCapabilities.self) private var caps
    @Environment(\.dismiss) private var dismiss

    @State private var camera = ItemCameraController()
    @State private var showReview = false
    @State private var draft: Item?
    @State private var alternatives: [ItemAlternative] = []
    @State private var isIdentifying = false
    @State private var manualW = "20"
    @State private var manualH = "10"
    @State private var manualD = "15"
    @State private var hint = ""
    @State private var errorText: String?
    @State private var useManualOnly = false

    private let client: any APIClient

    init(client: any APIClient) {
        self.client = client
    }

    private var showCamera: Bool {
        !caps.isSimulator && ItemCameraController.canUseCamera && !useManualOnly
    }

    var body: some View {
        ZStack {
            if showCamera {
                cameraStack
            } else {
                manualForm
            }

            if isIdentifying {
                Color.black.opacity(0.35).ignoresSafeArea()
                VStack(spacing: Tokens.Spacing.sm) {
                    ProgressView()
                    Text(Copy.Scan.waiting)
                        .font(Tokens.TypeScale.callout)
                        .foregroundStyle(.white)
                }
                .padding(Tokens.Spacing.lg)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Tokens.Radius.md))
            }
        }
        .navigationTitle(Copy.Scan.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if showCamera {
                await camera.start()
                if camera.statusMessage != nil {
                    useManualOnly = true
                    errorText = camera.statusMessage
                }
            }
        }
        .onDisappear { camera.stop() }
        .sheet(isPresented: $showReview) {
            if let draft {
                ReviewCardView(
                    item: draft,
                    alternatives: alternatives,
                    onSave: { item in
                        itemsStore.append(item)
                        showReview = false
                        dismiss()
                    },
                    onCancel: { showReview = false }
                )
                .presentationDetents([.medium, .large])
            }
        }
    }

    private var cameraStack: some View {
        VStack(spacing: 0) {
            Text(caps.measurementModeLabel)
                .font(Tokens.TypeScale.caption)
                .frame(maxWidth: .infinity)
                .padding(Tokens.Spacing.sm)
                .background(Tokens.Color.brandSecondary.opacity(0.25))

            ItemCameraPreview(controller: camera)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                HStack {
                    TextField("W", text: $manualW)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                    TextField("H", text: $manualH)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                    TextField("D", text: $manualD)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(.roundedBorder)
                    Text("cm").font(Tokens.TypeScale.caption)
                }
                TextField(Copy.Scan.hintPlaceholder, text: $hint)
                    .textFieldStyle(.roundedBorder)
                if let errorText {
                    Text(errorText).font(Tokens.TypeScale.caption).foregroundStyle(Tokens.Color.banned)
                }
                if let status = camera.statusMessage {
                    Text(status).font(Tokens.TypeScale.caption).foregroundStyle(Tokens.Color.restricted)
                }
                HStack {
                    Button(Copy.Scan.manualFallbackShort) { useManualOnly = true }
                        .font(Tokens.TypeScale.caption)
                    Spacer()
                    Button(Copy.Scan.capture) {
                        Task { await identifyFromCamera() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Tokens.Color.brand)
                    .disabled(isIdentifying || !camera.isRunning)
                }
            }
            .padding(Tokens.Spacing.md)
            .background(.ultraThinMaterial)
        }
    }

    private var manualForm: some View {
        Form {
            Section {
                Text(caps.measurementModeLabel)
                    .font(Tokens.TypeScale.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Dimensions (cm)") {
                TextField("Width", text: $manualW)
                    .keyboardType(.decimalPad)
                TextField("Height", text: $manualH)
                    .keyboardType(.decimalPad)
                TextField("Depth", text: $manualD)
                    .keyboardType(.decimalPad)
            }
            Section("Hint (optional)") {
                TextField("e.g. laptop charger", text: $hint)
            }
            if let errorText {
                Section { Text(errorText).foregroundStyle(Tokens.Color.banned) }
            }
            Section {
                if !caps.isSimulator && ItemCameraController.canUseCamera {
                    Button(Copy.Scan.useCamera) { useManualOnly = false }
                }
                Button(Copy.Scan.capture) {
                    Task { await identifyManual(imageBase64: nil) }
                }
                .disabled(isIdentifying)
            }
        }
    }

    private func identifyFromCamera() async {
        let image = await camera.captureJPEGBase64() ?? ImageCapture.placeholderBase64()
        await identifyManual(imageBase64: image)
    }

    private func identifyManual(imageBase64: String?) async {
        let w = Double(manualW) ?? 20
        let h = Double(manualH) ?? 10
        let d = Double(manualD) ?? 15
        let method: MeasureMethod = caps.hasLidar ? .manual : (caps.isSimulator ? .manual : .reference)
        let measured = MeasuredBox(w: w, h: h, d: d, confidence: method == .manual ? 1 : 0.7, method: method)
        await identify(measured: measured, imageBase64: imageBase64)
    }

    private func identify(measured: MeasuredBox, imageBase64: String?) async {
        isIdentifying = true
        errorText = nil
        defer { isIdentifying = false }
        let image = imageBase64 ?? ImageCapture.placeholderBase64()
        let dims = MeasuredDims(
            w: measured.w,
            h: measured.h,
            d: measured.d,
            method: measured.method,
            confidence: measured.confidence
        )
        do {
            let response = try await client.scanItem(
                imageBase64: image,
                measured: dims,
                reference: measured.method == .reference ? "credit_card" : nil,
                hint: hint.isEmpty ? nil : hint
            )
            draft = response.item
            alternatives = response.alternatives
            showReview = true
        } catch {
            draft = Item(
                id: UUID().uuidString,
                name: hint.isEmpty ? "Item" : hint,
                w: measured.w,
                h: measured.h,
                d: measured.d,
                kg: 0.3,
                category: .other,
                confidence: measured.confidence,
                source: .scan,
                measurement: Measurement(
                    method: measured.method,
                    confidence: measured.confidence,
                    deviceHasLidar: caps.hasLidar
                )
            )
            alternatives = []
            errorText = Copy.Scan.manualFallback
            showReview = true
        }
    }
}
