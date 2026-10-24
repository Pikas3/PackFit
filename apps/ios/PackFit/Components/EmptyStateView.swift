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
                .foregroundStyle(.secondary)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Tokens.Color.brand)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .packFitScreenPadding()
    }
}
