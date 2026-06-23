import SwiftUI

/// Brief loading step while a new wallet is generated (parent owns generation).
struct CreateWalletLaunchScreen: View {
    let onBack: () -> Void
    var errorMessage: String?

    var body: some View {
        ZStack {
            MeshTheme.Colors.background.ignoresSafeArea()

            if let errorMessage {
                VStack(spacing: 16) {
                    Text(errorMessage)
                        .font(MeshTheme.Typography.secondary())
                        .foregroundStyle(Color.orange)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    MeshSecondaryButton(title: "Go back", style: .outline, action: onBack)
                        .meshScreenFooterButtons()
                        .padding(.horizontal, MeshTheme.Metrics.screenPadding)
                }
            } else {
                ProgressView()
                    .tint(MeshTheme.Colors.textPrimary)
                    .scaleEffect(1.1)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}
