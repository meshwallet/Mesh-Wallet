import SwiftUI

/// Picker for sending USDT to another receive slot on the same wallet (excludes the current send-from slot).
struct MeshSendToSelfSheet: View {
    let slots: [WalletReceiveSlotOption]
    let isLoading: Bool
    let onSelect: (WalletReceiveSlotOption) -> Void

    private let rowCornerRadius: CGFloat = MeshTheme.Metrics.walletCardRadius
    private let rowSpacing: CGFloat = 10

    var body: some View {
        VStack(spacing: 0) {
            Text(L10n.Send.sendToSelf)
                .font(MeshTheme.Typography.sectionTitle())
                .foregroundStyle(MeshTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.top, 24)
                .padding(.bottom, 20)

            ScrollView(showsIndicators: false) {
                VStack(spacing: rowSpacing) {
                    ForEach(slots) { slot in
                        slotRow(slot)
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .padding(.horizontal, MeshTheme.Metrics.screenPadding)
        .preferredColorScheme(.dark)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color.black)
    }

    private func slotRow(_ slot: WalletReceiveSlotOption) -> some View {
        Button {
            onSelect(slot)
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    slotTitleRow(slot)

                    Text(ReceiveViewModel.receiveDisplayAddress(slot.address))
                        .font(MeshTheme.Typography.caption())
                        .foregroundStyle(MeshTheme.Colors.textTertiary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 8) {
                    MeshFlowAnimatedBalanceText(
                        text: slot.formattedBalance,
                        font: MeshTheme.Typography.sans(size: 15, weight: .semibold),
                        color: MeshTheme.Colors.textPrimary,
                        isPending: isLoading || slot.balanceUSDT == nil
                    )
                    .fixedSize(horizontal: true, vertical: false)

                    Image(systemName: "chevron.right")
                        .font(MeshTheme.Typography.icon(size: 11, weight: .semibold))
                        .foregroundStyle(MeshTheme.Colors.textTertiary.opacity(0.7))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background { slotRowBackground }
        }
        .buttonStyle(SlotRowButtonStyle())
        .disabled(isLoading)
        .accessibilityLabel(slot.title)
    }

    @ViewBuilder
    private func slotTitleRow(_ slot: WalletReceiveSlotOption) -> some View {
        HStack(spacing: 8) {
            Text(slot.title)
                .font(MeshTheme.Typography.sans(size: 15, weight: .semibold))
                .foregroundStyle(MeshTheme.Colors.textPrimary)
                .lineLimit(1)

            if slot.index == 0 {
                Text(L10n.Receive.mainBadge)
                    .font(MeshTheme.Typography.sans(size: 9, weight: .semibold))
                    .foregroundStyle(MeshTheme.Colors.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                    )
            }
        }
    }

    private var slotRowBackground: some View {
        RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
            .fill(MeshTheme.Colors.fieldFill)
    }
}

private struct SlotRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}
