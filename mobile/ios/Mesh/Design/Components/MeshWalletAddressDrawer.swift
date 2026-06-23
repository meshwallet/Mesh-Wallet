import SwiftUI

/// Left drawer panel — wallet receive accounts (overlay, content-sized).
struct MeshWalletAddressDrawer: View {
    static let widthRatio: CGFloat = 0.35
    static let screenLeadingInset: CGFloat = 12

    @Binding var isPresented: Bool
    @Binding var balanceHidden: Bool
    let panelWidth: CGFloat
    let panelTopInset: CGFloat
    let headerTopPadding: CGFloat
    let headerRowHeight: CGFloat
    let subaccountsIconSize: CGFloat
    let slots: [WalletReceiveSlotOption]
    let selectedIndex: UInt32
    let canAdd: Bool
    let isLoading: Bool
    let onSelect: (UInt32) -> Void
    let onAdd: () -> Void
    let onRename: (UInt32) -> Void
    let onDelete: (UInt32) -> Void

    private var horizontalPadding: CGFloat {
        max(10, panelWidth * 0.09)
    }

    private var rowTitleFontSize: CGFloat {
        max(11, min(14, panelWidth * 0.145))
    }

    private var balanceFontSize: CGFloat {
        max(11, min(13, panelWidth * 0.135))
    }

    private var usesLiquidGlass: Bool {
        MeshLiquidGlass.isSupported
    }

    private let drawerCornerRadius: CGFloat = 16
    private let rowCornerRadius: CGFloat = 10

    private var slotsLayoutSignature: String {
        slots.map { "\($0.id)" }.joined(separator: "|")
    }

    private var drawerRowTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .move(edge: .top))
                .combined(with: .scale(scale: 0.96, anchor: .topLeading)),
            removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .topLeading))
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            subaccountsHeader
                .padding(.top, headerTopPadding)
                .padding(.bottom, 14)

            VStack(spacing: 6) {
                ForEach(slots) { slot in
                    balanceRow(slot)
                        .transition(drawerRowTransition)
                }

                if canAdd {
                    addRow
                        .transition(.opacity)
                }
            }
            .animation(MeshBalanceRevealAnimation.listExpand, value: slotsLayoutSignature)
            .padding(.horizontal, max(4, horizontalPadding - 6))

            drawerFooterSubtitle
                .padding(.top, 10)
        }
        .padding(4)
        .frame(width: panelWidth, alignment: .topLeading)
        .background {
            MeshAccountsDrawerGlassBackground(cornerRadius: drawerCornerRadius)
                .clipShape(RoundedRectangle(cornerRadius: drawerCornerRadius, style: .continuous))
        }
        .shadow(
            color: Color.black.opacity(usesLiquidGlass ? 0.12 : 0.24),
            radius: usesLiquidGlass ? 14 : 20,
            x: 0,
            y: usesLiquidGlass ? 6 : 10
        )
        .padding(.top, panelTopInset)
    }

    private var subaccountsHeader: some View {
        HStack(spacing: 7) {
            Image("subaccounts")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: subaccountsIconSize, height: subaccountsIconSize)
                .foregroundStyle(MeshTheme.Colors.homeChromeIcon)

            Text(L10n.WalletAddressDrawer.title)
                .font(MeshTheme.Typography.sans(size: min(15, panelWidth * 0.17), weight: .medium))
                .foregroundStyle(MeshTheme.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: headerRowHeight, alignment: .center)
        .accessibilityElement(children: .combine)
    }

    private var drawerFooterSubtitle: some View {
        Text(L10n.WalletAddressDrawer.subtitle)
            .font(MeshTheme.Typography.sans(size: 9, weight: .regular))
            .foregroundStyle(MeshTheme.Colors.textTertiary.opacity(0.8))
            .multilineTextAlignment(.center)
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .allowsTightening(true)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, horizontalPadding)
            .padding(.bottom, 10)
    }

    private func drawerRowBorder(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
            .strokeBorder(
                isSelected
                    ? MeshTheme.Colors.accent.opacity(0.55)
                    : MeshTheme.Colors.borderSubtle.opacity(0.7),
                lineWidth: 1
            )
    }

    @ViewBuilder
    private func balanceRow(_ slot: WalletReceiveSlotOption) -> some View {
        let isSelected = slot.index == selectedIndex
        let row = rowContent(slot, isSelected: isSelected)

        Group {
            if slot.index > 0 {
                Menu {
                    Button {
                        onRename(slot.index)
                    } label: {
                        MeshContextMenuLabel(
                            title: L10n.WalletAddressDrawer.renameAccountAccessibility,
                            systemImage: "pencil"
                        )
                    }

                    Button {
                        onDelete(slot.index)
                    } label: {
                        MeshContextMenuLabel(
                            title: L10n.Receive.deleteAddressAction,
                            systemImage: "trash",
                            isDestructive: true
                        )
                    }
                } label: {
                    row
                } primaryAction: {
                    selectSlot(slot.index)
                }
                .tint(.white)
            } else {
                Button {
                    selectSlot(slot.index)
                } label: {
                    row
                }
            }
        }
        .buttonStyle(.plain)
        .meshLiquidGlassButton(
            enabled: usesLiquidGlass && isSelected,
            role: .regular,
            shape: .roundedRectangle(radius: rowCornerRadius)
        )
    }

    private func rowContent(_ slot: WalletReceiveSlotOption, isSelected: Bool) -> some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 4) {
                slotTitle(slot, isSelected: isSelected)
                    .frame(maxWidth: .infinity, alignment: .leading)

                slotBalance(slot, isSelected: isSelected)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            balanceIndicator(for: slot)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if !usesLiquidGlass {
                RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                    .fill(
                        isSelected
                            ? MeshTheme.Colors.fieldFill.opacity(0.88)
                            : MeshTheme.Colors.fieldFill.opacity(0.45)
                    )
            }
        }
        .overlay {
            drawerRowBorder(isSelected: isSelected)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func balanceIndicator(for slot: WalletReceiveSlotOption) -> some View {
        if !slot.address.isEmpty, (slot.balanceUSDT ?? 0) >= 1 {
            Circle()
                .fill(MeshTheme.Colors.success)
                .frame(width: 3, height: 3)
                .padding(.top, 2)
                .padding(.trailing, 2)
                .accessibilityLabel(L10n.WalletAddressDrawer.activationActive)
        }
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            isPresented = false
        }
    }

    private func selectSlot(_ index: UInt32) {
        onSelect(index)
        dismiss()
    }

    @ViewBuilder
    private func slotTitle(_ slot: WalletReceiveSlotOption, isSelected: Bool) -> some View {
        if slot.index == 0, !hasCustomReceiveName(slot) {
            Text(L10n.WalletAddressDrawer.mainBadge)
                .font(MeshTheme.Typography.sans(size: max(10, rowTitleFontSize - 1), weight: .semibold))
                .foregroundStyle(MeshTheme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(MeshTheme.Colors.fieldFillPressed, in: Capsule())
        } else {
            Text(slot.title)
                .font(
                    MeshTheme.Typography.sans(
                        size: rowTitleFontSize,
                        weight: slot.index == 0 ? .semibold : .light
                    )
                )
                .foregroundStyle(
                    isSelected
                        ? MeshTheme.Colors.textPrimary
                        : MeshTheme.Colors.textSecondary
                )
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func hasCustomReceiveName(_ slot: WalletReceiveSlotOption) -> Bool {
        guard let walletID = MeshWalletRegistry.activeWalletID else { return false }
        return MeshPrivacyStore.receiveSlotCustomName(index: slot.index, walletID: walletID) != nil
    }

    private func slotBalance(_ slot: WalletReceiveSlotOption, isSelected: Bool) -> some View {
        MeshFlowAnimatedBalanceText(
            text: slot.formattedBalance,
            font: MeshTheme.Typography.sans(size: balanceFontSize, weight: .semibold),
            color: isSelected
                ? MeshTheme.Colors.textPrimary
                : MeshTheme.Colors.textSecondary,
            isPending: isLoading || slot.balanceUSDT == nil
        )
        .walletHomeBalancePrivacyBlur(isHidden: balanceHidden, blurRadius: 6)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var addRow: some View {
        Button(action: onAdd) {
            ZStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(" ")
                        .font(MeshTheme.Typography.sans(size: rowTitleFontSize, weight: .semibold))
                        .opacity(0)
                        .accessibilityHidden(true)

                    Text(" ")
                        .font(MeshTheme.Typography.sans(size: balanceFontSize, weight: .semibold))
                        .opacity(0)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "plus")
                    .font(MeshTheme.Typography.icon(size: max(14, panelWidth * 0.16), weight: .medium))
                    .foregroundStyle(
                        usesLiquidGlass
                            ? MeshTheme.Colors.textTertiary
                            : MeshTheme.Colors.textTertiary.opacity(0.55)
                    )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay {
                drawerRowBorder(isSelected: false)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .meshLiquidGlassButton(
            enabled: usesLiquidGlass,
            role: .regular,
            shape: .roundedRectangle(radius: rowCornerRadius)
        )
        .disabled(isLoading)
        .opacity(usesLiquidGlass ? 0.82 : 1)
        .accessibilityLabel(L10n.WalletAddressDrawer.generateBalance)
    }
}
