import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MeshTransferProofExperience: View {
    let transaction: WalletTransaction
    let onClose: () -> Void
    var usesSheetChrome: Bool = true

    @State private var sharePayload: SharePayload?
    @State private var didCopyTx = false
    @State private var isPreparingShare = false
    @State private var shareFlashOpacity: Double = 0
    @State private var screenshotHintVisible = false
    @State private var inAppBrowserURL: URL?

    private let sharePrepareSpring = Animation.spring(response: 0.48, dampingFraction: 0.82)
    private let shareReleaseSpring = Animation.spring(response: 0.42, dampingFraction: 0.88)

    var body: some View {
        ZStack(alignment: .top) {
            background

            standardProofContent

            if isPreparingShare {
                Color.black.opacity(0.28)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            if shareFlashOpacity > 0 {
                Color.white.opacity(shareFlashOpacity)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }

            if screenshotHintVisible {
                screenshotHint
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .preferredColorScheme(.dark)
        .animation(sharePrepareSpring, value: isPreparingShare)
        .animation(.easeOut(duration: 0.22), value: shareFlashOpacity)
        .animation(.easeInOut(duration: 0.25), value: screenshotHintVisible)
        #if canImport(UIKit)
        .sheet(item: $sharePayload) { payload in
            MeshShareSheet(items: payload.items)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.userDidTakeScreenshotNotification)) { _ in
            guard !isPreparingShare else { return }
            presentScreenshotHint()
        }
        #endif
        .sheet(isPresented: Binding(
            get: { inAppBrowserURL != nil },
            set: { if !$0 { inAppBrowserURL = nil } }
        )) {
            if let url = inAppBrowserURL {
                MeshInAppBrowserSheet(url: url)
                    .ignoresSafeArea()
            }
        }
    }

    @ViewBuilder
    private var background: some View {
        if usesSheetChrome {
            MeshSelectWalletSheetBackground()
        } else {
            MeshTheme.Colors.background.ignoresSafeArea()
        }
    }

    private var standardProofContent: some View {
        VStack(spacing: 0) {
            header
                .opacity(isPreparingShare ? 0.35 : 1)
                .blur(radius: isPreparingShare ? 1.5 : 0)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Text(transaction.proofHeadline)
                            .font(MeshTheme.Typography.sans(size: 22, weight: .semibold))
                            .foregroundStyle(MeshTheme.Colors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .opacity(isPreparingShare ? 0.4 : 1)

                        Text(transaction.proofSubtitle)
                            .font(MeshTheme.Typography.caption())
                            .foregroundStyle(MeshTheme.Colors.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .opacity(isPreparingShare ? 0.35 : 1)
                    }

                    MeshTransferProofCard(transaction: transaction, style: .standard)
                        .scaleEffect(isPreparingShare ? 1.04 : 1, anchor: .center)
                        .shadow(
                            color: MeshTheme.Colors.accent.opacity(isPreparingShare ? 0.35 : 0),
                            radius: isPreparingShare ? 22 : 0,
                            y: isPreparingShare ? 6 : 0
                        )
                        .overlay {
                            if isPreparingShare {
                                RoundedRectangle(cornerRadius: MeshTheme.Metrics.cardRadius, style: .continuous)
                                    .strokeBorder(
                                        MeshTheme.Colors.accent.opacity(0.55),
                                        lineWidth: 1.5
                                    )
                                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                            }
                        }
                }
                .padding(.horizontal, MeshTheme.Metrics.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }

            if !transaction.isProcessing {
                footerActions
                    .meshScreenFooterButtons()
                    .padding(.horizontal, MeshTheme.Metrics.screenPadding)
                    .padding(.top, 12)
                    .padding(.bottom, 16)
                    .opacity(isPreparingShare ? 0 : 1)
                    .offset(y: isPreparingShare ? 18 : 0)
                    .allowsHitTesting(!isPreparingShare)
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        if usesSheetChrome {
            VStack(spacing: 0) {
                Capsule()
                    .fill(MeshTheme.Colors.textTertiary.opacity(0.3))
                    .frame(width: 36, height: 4)
                    .padding(.top, 8)
                    .padding(.bottom, 20)

                HStack {
                    Spacer()
                    Button(L10n.Common.done, action: onClose)
                        .buttonStyle(.plain)
                        .font(MeshTheme.Typography.secondary())
                        .foregroundStyle(MeshTheme.Colors.textSecondary)
                        .disabled(isPreparingShare)
                }
                .padding(.horizontal, MeshTheme.Metrics.screenPadding)
                .padding(.bottom, 4)
            }
        } else {
            HStack {
                MeshChromeButton.close(action: onClose)
                    .disabled(isPreparingShare)
                Spacer()
                Button(L10n.Common.done, action: onClose)
                    .buttonStyle(.plain)
                    .font(MeshTheme.Typography.secondary())
                    .foregroundStyle(MeshTheme.Colors.textSecondary)
                    .disabled(isPreparingShare)
            }
            .padding(.horizontal, MeshTheme.Metrics.screenPadding)
            .padding(.top, 4)
        }
    }

    private var footerActions: some View {
        VStack(spacing: 12) {
            MeshPrimaryButton(
                title: L10n.TransferProof.shareProof,
                icon: "square.and.arrow.up",
                isEnabled: !isPreparingShare
            ) {
                shareCleanProof()
            }
            MeshSecondaryButton(
                title: didCopyTx ? L10n.Common.copied : L10n.TransferProof.copyTx,
                icon: didCopyTx ? "checkmark" : "link",
                isEnabled: !transaction.txID.isEmpty && !isPreparingShare
            ) {
                copyTx()
            }
            if transaction.tronscanURL != nil {
                MeshSecondaryButton(
                    title: L10n.TransferProof.viewOnTronscan,
                    icon: "arrow.up.right",
                    isEnabled: !isPreparingShare
                ) {
                    openTronscan()
                }
            }
        }
    }

    private var screenshotHint: some View {
        VStack {
            Spacer()
            Text(L10n.TransferProof.screenshotHint)
                .font(MeshTheme.Typography.caption())
                .foregroundStyle(MeshTheme.Colors.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(MeshTheme.Colors.surfaceElevated, in: Capsule())
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
        }
    }

    private func shareCleanProof() {
        #if canImport(UIKit)
        guard !isPreparingShare else { return }
        Task { @MainActor in
            withAnimation(sharePrepareSpring) {
                isPreparingShare = true
            }

            try? await Task.sleep(nanoseconds: 340_000_000)

            guard let image = await renderShareImage() else {
                withAnimation(shareReleaseSpring) {
                    isPreparingShare = false
                }
                return
            }

            withAnimation(.easeOut(duration: 0.14)) {
                shareFlashOpacity = 0.14
            }
            try? await Task.sleep(nanoseconds: 120_000_000)

            withAnimation(shareReleaseSpring) {
                isPreparingShare = false
                shareFlashOpacity = 0
            }
            try? await Task.sleep(nanoseconds: 220_000_000)

            sharePayload = SharePayload(items: [image, transaction.proofShareText])
        }
        #endif
    }

    @MainActor
    private func renderShareImage(maxAttempts: Int = 3) async -> UIImage? {
        for attempt in 0..<maxAttempts {
            if let image = MeshTransferProofImageRenderer.image(for: transaction) {
                return image
            }
            guard attempt + 1 < maxAttempts else { break }
            await Task.yield()
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return nil
    }

    private func copyTx() {
        guard !transaction.txID.isEmpty, MeshClipboard.copy(transaction.txID) else { return }
        didCopyTx = true
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await MainActor.run { didCopyTx = false }
        }
    }

    private func openTronscan() {
        guard let url = transaction.tronscanURL else { return }
        inAppBrowserURL = url
    }

    private func presentScreenshotHint() {
        screenshotHintVisible = true
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            await MainActor.run { screenshotHintVisible = false }
        }
    }
}

#if canImport(UIKit)
private struct SharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}
#endif
