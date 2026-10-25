import SwiftUI

struct OnboardingView: View {
    @Binding var hasSeen: Bool
    @State private var page = 0

    private let pages: [(title: String, body: String)] = [
        (Copy.Onboarding.s1Title, Copy.Onboarding.s1Body),
        (Copy.Onboarding.s2Title, Copy.Onboarding.s2Body),
        (Copy.Onboarding.s3Title, Copy.Onboarding.s3Body)
    ]

    private let icons = ["camera.metering.matrix", "cube", "checkmark.shield"]

    var body: some View {
        VStack(spacing: Tokens.Spacing.lg) {
            HStack {
                Spacer()
                Button(Copy.Onboarding.skip) { hasSeen = true }
                    .font(Tokens.TypeScale.callout)
            }

            Spacer()
            Image(systemName: icons[page])
                .font(.system(size: 40, weight: .medium))
                .foregroundStyle(Tokens.Palette.pink800)
                .frame(width: 96, height: 96)
                .background(Tokens.Palette.pink300, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
                .shadow(color: Tokens.Palette.buttonShadow, radius: 10, y: 8)
                .accessibilityHidden(true)
            (Text(Copy.App.wordmarkLead).foregroundStyle(Tokens.Palette.textPrimary) + Text(Copy.App.wordmarkTail).foregroundStyle(Tokens.Palette.pink700))
                .font(Tokens.TypeScale.display)
            Text(pages[page].title)
                .font(Tokens.TypeScale.h1)
                .foregroundStyle(Tokens.Palette.textPrimary)
                .multilineTextAlignment(.center)
            Text(pages[page].body)
                .font(Tokens.TypeScale.body)
                .foregroundStyle(Tokens.Palette.textSecondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 6) {
                ForEach(pages.indices, id: \.self) { i in
                    Capsule()
                        .fill(i == page ? Tokens.Palette.pink700 : Tokens.Palette.pink200)
                        .frame(width: i == page ? 20 : 8, height: 8)
                }
            }
            .accessibilityHidden(true)
            Spacer()

            Button(page == pages.count - 1 ? Copy.Onboarding.done : Copy.Onboarding.next) {
                if page == pages.count - 1 {
                    hasSeen = true
                } else {
                    withAnimation(.easeInOut(duration: Tokens.Motion.standard)) { page += 1 }
                }
            }
            .buttonStyle(.snuglyPrimary)
        }
        .padding(.horizontal, Tokens.Spacing.screen)
        .padding(.vertical, Tokens.Spacing.md)
        .background { BlobBackground().ignoresSafeArea() }
        .font(Tokens.TypeScale.base)
    }
}
