import SwiftUI

struct ScanView: View {
    @Environment(ItemsStore.self) private var itemsStore
    @Environment(DeviceCapabilities.self) private var caps
    @Environment(\.dismiss) private var dismiss

    @State private var controller: LidarSessionController
    @State private var showReview = false
    @State private var draft: Item?
    @State private var alternatives: [ItemAlternative] = []
    @State private var isIdentifying = false
    @State private var manualW = "20"
    @State private var manualH = "10"
    @State private var manualD = "15"
    @State private var hint = ""
    @State private var errorText: String?
    @State private var useManualForm = false

    private let client: any APIClient

    init(client: any APIClient, hasLidar: Bool) {
        self.client = client
        _controller = State(initialValue: LidarSessionController(hasLidar: hasLidar))
    }

    var body: some View {
        ZStack {
            if caps.isSimulator || useManualForm || !caps.hasLidar {
                manualForm
            } else {
                lidarStack
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
        .onAppear {
            if caps.hasLidar && !caps.isSimulator {
                controller.start()
            } else {
                useManualForm = true
            }
        }
        .onDisappear { controller.stop() }
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

    private var lidarStack: some View {
        VStack(spacing: 0) {
            Text(caps.measurementModeLabel)
                .font(Tokens.TypeScale.caption)
                .frame(maxWidth: .infinity)
                .padding(Tokens.Spacing.sm)
                .background(Tokens.Color.brandSecondary.opacity(0.25))

            ARScanRepresentable(controller: controller)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                Text(controller.statusText)
                    .font(Tokens.TypeScale.body)
                if let box = controller.previewBox {
                    Text(String(format: "%.1f × %.1f × %.1f cm", box.w, box.h, box.d))
                        .font(Tokens.TypeScale.title)
                    ConfidenceBadge(confidence: box.confidence)
                    HStack {
                        Button(Copy.Scan.retap) { controller.resetMeasurement() }
                        Spacer()
                        Button(Copy.Scan.capture) { Task { await identify(measured: box) } }
                            .buttonStyle(.borderedProminent)
                            .tint(Tokens.Color.brand)
                    }
                }
                if let errorText {
                    Text(errorText).foregroundStyle(Tokens.Color.banned).font(Tokens.TypeScale.caption)
                }
                Button("Enter dimensions instead") { useManualForm = true }
                    .font(Tokens.TypeScale.caption)
            }
            .packFitScreenPadding()
            .background(Tokens.Color.surface)
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
                Button(Copy.Scan.capture) {
                    Task { await identifyManual() }
                }
                .disabled(isIdentifying)
            }
        }
    }

    private func identifyManual() async {
        let w = Double(manualW) ?? 20
        let h = Double(manualH) ?? 10
        let d = Double(manualD) ?? 15
        let method: MeasureMethod = caps.hasLidar ? .manual : (caps.isSimulator ? .manual : .reference)
        let measured = MeasuredDims(w: w, h: h, d: d, method: method, confidence: method == .manual ? 1 : 0.7)
        await identify(measured: MeasuredBox(w: w, h: h, d: d, confidence: measured.confidence, method: method))
    }

    private func identify(measured: MeasuredBox) async {
        isIdentifying = true
        errorText = nil
        defer { isIdentifying = false }
        let image = controller.lastCapturedBase64 ?? ImageCapture.placeholderBase64()
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
            // Keep measured dims; drop to editable manual card.
            draft = Item(
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
                    deviceHasLidar: measured.method == .lidar
                )
            )
            alternatives = []
            errorText = Copy.Scan.manualFallback
            showReview = true
        }
    }
}
