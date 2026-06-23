import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ReceiveUSDTView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.meshModalClose) private var meshModalClose
    @Environment(\.meshInteractiveDismiss) private var meshInteractiveDismiss
    @StateObject private var model = ReceiveViewModel()
    @State private var showShareSheet = false
    @State private var isAddressListExpanded = false

    var body: some View {
        ZStack {
            MeshTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                MeshFlowScreenHeader(title: L10n.Receive.title, onClose: closeModal)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        qrSection
                            .padding(.top, 12)

                        if model.receiveSlots.count > 1 {
                            addressPickerSection
                                .padding(.top, 24)
                        }

                        addressSection
                            .padding(.top, 28)

                        if let loadError = model.loadError {
                            Text(loadError)
                                .font(MeshTheme.Typography.caption())
                                .foregroundStyle(Color.orange)
                                .multilineTextAlignment(.center)
                                .padding(.top, 12)
                        }

                        actionButtons
                            .meshScreenFooterButtons()
                            .padding(.top, 28)
                            .padding(.bottom, 16)
                    }
                    .padding(.horizontal, MeshTheme.Metrics.screenPadding)
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .scrollBounceBehavior(.always, axes: .vertical)
            }
        }
        .task { await model.load() }
        .onChange(of: model.didCopyAddress) { copied in
            guard copied else { return }
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run { model.didCopyAddress = false }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            MeshShareSheet(items: [model.shareText])
        }
        .preferredColorScheme(.dark)
        .animation(MeshBalanceRevealAnimation.reveal, value: model.receiveSlots.map(\.balanceUSDT))
        .animation(MeshBalanceRevealAnimation.listExpand, value: isAddressListExpanded)
    }

    private func closeModal() {
        MeshModalClose.perform(
            modalClose: meshModalClose,
            interactiveDismiss: meshInteractiveDismiss,
            dismiss: dismiss
        )
    }

    // MARK: - QR

    private var qrSection: some View {
        VStack(spacing: 16) {
            qrCard
                .frame(maxWidth: 280)
                .frame(maxWidth: .infinity)
                .aspectRatio(1, contentMode: .fit)
                .id(model.qrRefreshID)

            Text(model.captionText)
                .font(MeshTheme.Typography.sans(size: 12, weight: .regular))
                .foregroundStyle(MeshTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
        }
    }

    private var qrCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white)

            if model.walletAddress.isEmpty {
                ProgressView()
                    .tint(Color.black.opacity(0.4))
                    .padding(48)
            } else {
                #if canImport(UIKit)
                MeshQRCodeImage(payload: model.walletAddress)
                    .padding(28)
                #endif
            }

            usdtBadge
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private var usdtBadge: some View {
        ZStack {
            Circle()
                .fill(Color(hex: 0x26A17B))
                .frame(width: 44, height: 44)
            Image(systemName: "dollarsign")
                .font(MeshTheme.Typography.icon(size: 18, weight: .semibold))
                .foregroundStyle(Color.white)
        }
    }

    // MARK: - Address picker (collapsible)

    private var addressPickerSection: some View {
        MeshWalletSlotPickerView(
            headerTitle: L10n.Receive.receiveOnAddress,
            slots: model.receiveSlots,
            selectedIndex: model.receiveAccountIndex,
            isExpanded: $isAddressListExpanded,
            isLoading: model.isLoading,
            showsBalance: true
        ) { index in
            model.selectSlot(index)
        }
    }

    // MARK: - Address

    private var addressSection: some View {
        VStack(spacing: 12) {
            Button {
                model.copyAddress()
            } label: {
                HStack(spacing: 10) {
                    Text(model.displayAddress)
                        .font(MeshTheme.Typography.body())
                        .foregroundStyle(MeshTheme.Colors.textPrimary)
                        .lineLimit(1)

                    Image(systemName: "link")
                        .font(MeshTheme.Typography.icon(size: 14, weight: .medium))
                        .foregroundStyle(MeshTheme.Colors.textSecondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .background(MeshTheme.Colors.fieldFill, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(model.walletAddress.isEmpty)

            Text(L10n.Common.copied)
                .font(MeshTheme.Typography.caption())
                .foregroundStyle(MeshTheme.Colors.success)
                .opacity(model.didCopyAddress ? 1 : 0)
                .frame(height: 18)
                .accessibilityHidden(!model.didCopyAddress)

            Text("Network: Tron (TRC-20)")
                .font(MeshTheme.Typography.caption())
                .foregroundStyle(MeshTheme.Colors.textTertiary)
        }
    }

    // MARK: - Actions

    private var actionButtons: some View {
        MeshSecondaryButton(
            title: "Share address",
            isEnabled: !model.walletAddress.isEmpty && !model.isLoading
        ) {
            showShareSheet = true
        }
    }
}
