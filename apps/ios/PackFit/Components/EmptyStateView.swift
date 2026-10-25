import SwiftUI

struct EmptyStateView: View {
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(_ message: String, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: Tokens.Spacing.md) {
            Text(message)
                .font(Tokens.TypeScale.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(Tokens.Palette.textSecondary)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.snuglyPrimary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .snuglyScreenPadding()
    }
}
