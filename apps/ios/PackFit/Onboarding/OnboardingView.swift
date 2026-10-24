import SwiftUI

struct OnboardingView: View {
    @Binding var hasSeen: Bool
    @State private var page = 0

    private let pages: [(title: String, body: String)] = [
        (Copy.Onboarding.s1Title, Copy.Onboarding.s1Body),
        (Copy.Onboarding.s2Title, Copy.Onboarding.s2Body),
        (Copy.Onboarding.s3Title, Copy.Onboarding.s3Body)
    ]

    var body: some View {
        VStack(spacing: Tokens.Spacing.lg) {
            HStack {
                Spacer()
                Button(Copy.Onboarding.skip) { hasSeen = true }
                    .font(Tokens.TypeScale.callout)
            }

            Spacer()
            Text(Copy.App.name)
                .font(Tokens.TypeScale.hero)
                .foregroundStyle(Tokens.Color.brand)
            Text(pages[page].title)
                .font(Tokens.TypeScale.title)
                .multilineTextAlignment(.center)
            Text(pages[page].body)
                .font(Tokens.TypeScale.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()

            Button(page == pages.count - 1 ? Copy.Onboarding.done : Copy.Onboarding.next) {
                if page == pages.count - 1 {
                    hasSeen = true
                } else {
                    withAnimation(.easeInOut(duration: Tokens.Motion.standard)) { page += 1 }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Tokens.Color.brand)
            .frame(maxWidth: .infinity)
        }
        .packFitScreenPadding()
        .background(
            LinearGradient(
                colors: [Tokens.Color.surface, Tokens.Color.brandSecondary.opacity(0.25)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }
}
