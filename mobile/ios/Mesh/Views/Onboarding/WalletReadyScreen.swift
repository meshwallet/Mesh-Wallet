import SwiftUI

struct WalletReadyScreen: View {
    let onStart: () -> Void

    @State private var videoOpacity: Double = 0

    var body: some View {
        ZStack {
            MeshTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                videoHero
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(1)
                    .ignoresSafeArea(edges: .top)

                bottomPanel
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
    }

    private var videoHero: some View {
        ZStack(alignment: .bottom) {
            #if canImport(UIKit)
            MeshBundleVideoPlayer(
                resourceName: "Wallet",
                fileExtension: "mp4",
                loops: true,
                onReady: {
                    withAnimation(.easeIn(duration: 0.75)) {
                        videoOpacity = 1
                    }
                }
            )
            .opacity(videoOpacity)
            #endif

            LinearGradient(
                colors: [
                    Color.clear,
                    MeshTheme.Colors.background.opacity(0.35),
                    MeshTheme.Colors.background
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 120)
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(MeshTheme.Colors.background)
    }

    private var bottomPanel: some View {
        VStack(spacing: 28) {
            VStack(spacing: 8) {
                Text(L10n.Onboarding.walletReadyTitle)
                    .font(MeshTheme.Typography.sans(size: 34, weight: .semibold))
                    .foregroundStyle(MeshTheme.Colors.textPrimary)

                Text(L10n.Onboarding.walletReadySubtitle)
                    .font(MeshTheme.Typography.secondary())
                    .foregroundStyle(MeshTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)

            MeshPrimaryButton(title: L10n.Onboarding.walletReadyOpen, action: onStart)
                .meshScreenFooterButtons()
        }
        .padding(.horizontal, MeshTheme.Metrics.screenPadding)
        .padding(.top, 4)
        .padding(.bottom, 12)
        .background(MeshTheme.Colors.background)
    }
}
