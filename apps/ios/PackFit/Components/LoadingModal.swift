import SwiftUI

private typealias P = Tokens.Palette
private typealias T = Tokens.TypeScale

/// Blocking spinner card for waits the user can't skip: identifying scanned items, packing.
struct LoadingModal: View {
    let title: String
    var message: String?
    var detail: String?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var spinning = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
            VStack(spacing: Tokens.Spacing.md) {
                spinner
                VStack(spacing: Tokens.Spacing.xs) {
                    Text(title)
                        .font(T.h2)
                        .foregroundStyle(P.textPrimary)
                    if let message {
                        Text(message)
                            .font(T.body)
                            .foregroundStyle(P.textSecondary)
                    }
                    if let detail {
                        Text(detail)
                            .font(T.bodyBold)
                            .foregroundStyle(P.pink700)
                            .monospacedDigit()
                    }
                }
                .multilineTextAlignment(.center)
            }
            .padding(Tokens.Spacing.lg)
            .frame(maxWidth: 280)
            .background(P.surface, in: RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous))
            .shadow(color: P.shadow, radius: 12, y: 8)
            .padding(Tokens.Spacing.screen)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.updatesFrequently)
        }
        // Swallow taps so nothing underneath can be pressed mid-wait.
        .contentShape(Rectangle())
        .onTapGesture {}
        .onAppear { spinning = true }
    }

    @ViewBuilder
    private var spinner: some View {
        if reduceMotion {
            ProgressView()
                .controlSize(.large)
                .tint(P.pink700)
        } else {
            ZStack {
                Circle()
                    .stroke(P.pink100, lineWidth: 5)
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(P.pink700, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(spinning ? 360 : 0))
                    .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: spinning)
            }
            .frame(width: 44, height: 44)
            .accessibilityHidden(true)
        }
    }
}

extension View {
    /// Covers this view with a `LoadingModal` while `isPresented` is true. Once shown it stays
    /// up for at least `minimumSeconds`, so a fast result doesn't flash the card.
    func loadingModal(
        isPresented: Bool,
        title: String,
        message: String? = nil,
        detail: String? = nil,
        minimumSeconds: Double = 0.6
    ) -> some View {
        modifier(LoadingModalModifier(
            isPresented: isPresented, title: title, message: message, detail: detail,
            minimumSeconds: minimumSeconds
        ))
    }
}

private struct LoadingModalModifier: ViewModifier {
    let isPresented: Bool
    let title: String
    let message: String?
    let detail: String?
    let minimumSeconds: Double

    @State private var isShowing = false
    @State private var shownAt: Date?

    func body(content: Content) -> some View {
        content
            .overlay {
                if isShowing {
                    LoadingModal(title: title, message: message, detail: detail)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: Tokens.Motion.quick), value: isShowing)
            .task(id: isPresented) {
                if isPresented {
                    shownAt = .now
                    isShowing = true
                } else if isShowing {
                    let elapsed = Date.now.timeIntervalSince(shownAt ?? .now)
                    if elapsed < minimumSeconds {
                        try? await Task.sleep(for: .seconds(minimumSeconds - elapsed))
                    }
                    // A new wait started while sleeping: keep the card up.
                    guard !Task.isCancelled else { return }
                    isShowing = false
                }
            }
    }
}

#Preview {
    Color.clear
        .snuglyCanvas()
        .loadingModal(isPresented: true, title: "Identifying items", message: "Usually 3–8 seconds.")
}
