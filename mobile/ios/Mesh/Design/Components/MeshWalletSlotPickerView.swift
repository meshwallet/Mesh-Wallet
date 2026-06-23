import SwiftUI

/// Collapsible picker for the five wallet receive/send slots (same UX as Receive).
struct MeshWalletSlotPickerView: View {
    let headerTitle: String
    let slots: [WalletReceiveSlotOption]
    let selectedIndex: UInt32
    @Binding var isExpanded: Bool
    var showsHeader: Bool = true
    var isLoading: Bool = false
    var showsBalance: Bool = true
    var balanceHidden: Bool = false
    var usesOpaqueCards: Bool = false
    /// Home hero: fit all rows in this height (compact, no scroll).
    var maxExpandedListHeight: CGFloat?
    /// Home: compact “Show more” row. Receive/Send: stacked address preview cards.
    var collapsedPresentation: CollapsedPresentation = .stackedPreview
    var onLongPress: ((UInt32) -> Void)?
    let onSelect: (UInt32) -> Void

    /// Layout height for hero spacers on home (collapsed stacked preview).
    static func preferredHeight(
        slotCount: Int,
        isExpanded: Bool,
        includesAddFooter: Bool,
        showsHeader: Bool = true,
        maxExpandedListHeight: CGFloat? = nil
    ) -> CGFloat {
        let header: CGFloat = showsHeader ? 34 : 0
        let showMore: CGFloat = 36
        let addFooter: CGFloat = 52

        var height = header
        let count = max(1, slotCount)
        if isExpanded {
            if let maxExpandedListHeight {
                height += maxExpandedListHeight
            } else {
                height += ExpandedFitLayout.standard(slotCount: count).totalHeight(slotCount: count)
            }
        } else {
            height += ExpandedFitLayout.standard(slotCount: count).rowHeight
            height += showMore
        }
        if includesAddFooter {
            height += addFooter
        }
        return height
    }

    enum CollapsedPresentation {
        case stackedPreview
        case compactSummary
    }

    private var balanceLoadSignature: String {
        slots
            .map { "\($0.id)-\($0.balanceUSDT?.description ?? "nil")" }
            .joined(separator: "|")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsHeader {
                Button(action: toggleList) {
                    Text(headerTitle)
                        .font(MeshTheme.Typography.caption())
                        .foregroundStyle(MeshTheme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            Group {
                if isExpanded {
                    expandedSlotList
                } else {
                    collapsedStack
                }
            }
        }
        .animation(MeshBalanceRevealAnimation.listExpand, value: isExpanded)
        .animation(MeshBalanceRevealAnimation.reveal, value: balanceLoadSignature)
        .animation(MeshBalanceRevealAnimation.reveal, value: isLoading)
    }

    private func slotBalanceRevealed(_ slot: WalletReceiveSlotOption, index: Int) -> Bool {
        guard showsBalance else { return true }
        if isLoading { return false }
        return slot.balanceUSDT != nil
    }

    private var pendingBalanceOpacity: Double {
        usesOpaqueCards ? 1 : 0.72
    }

    private var expandedFitLayout: ExpandedFitLayout {
        if let maxExpandedListHeight {
            return ExpandedFitLayout.fitting(
                slotCount: slots.count,
                availableHeight: maxExpandedListHeight
            )
        }
        return ExpandedFitLayout.standard(slotCount: slots.count)
    }

    private var expandedSlotList: some View {
        let layout = expandedFitLayout
        return VStack(spacing: layout.rowSpacing) {
            ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                slotRow(slot, style: .expanded(fit: layout))
                    .frame(height: layout.rowHeight)
                    .opacity(slotBalanceRevealed(slot, index: index) ? 1 : pendingBalanceOpacity)
                    .offset(y: usesOpaqueCards || slotBalanceRevealed(slot, index: index) ? 0 : 4)
                    .animation(
                        MeshBalanceRevealAnimation.staggeredReveal(index: index),
                        value: balanceLoadSignature
                    )
            }
        }
    }

    @ViewBuilder
    private var collapsedStack: some View {
        switch collapsedPresentation {
        case .stackedPreview:
            stackedPreviewCollapsed
        case .compactSummary:
            compactSummaryCollapsed
        }
    }

    private var collapsedRowLayout: ExpandedFitLayout {
        expandedFitLayout
    }

    private var stackedPreviewCollapsed: some View {
        VStack(spacing: 0) {
            if let selected = slots.first(where: { $0.index == selectedIndex }) ?? slots.first {
                let layout = collapsedRowLayout
                Button(action: expandList) {
                    slotCard(selected, style: .expanded(fit: layout), isSelected: true)
                }
                .buttonStyle(.plain)
                .disabled(isLoading)
                .frame(height: layout.rowHeight)
                .opacity(slotBalanceRevealed(selected, index: 0) ? 1 : pendingBalanceOpacity)
                .offset(y: usesOpaqueCards || slotBalanceRevealed(selected, index: 0) ? 0 : 4)
                .animation(MeshBalanceRevealAnimation.reveal, value: balanceLoadSignature)
            }

            showMoreRow
        }
    }

    private var compactSummaryCollapsed: some View {
        showMoreRow
    }

    private var showMoreRow: some View {
        Button(action: expandList) {
            HStack(spacing: 6) {
                Text(L10n.Receive.showMore)
                    .font(MeshTheme.Typography.caption())
                    .foregroundStyle(MeshTheme.Colors.textSecondary)
                Image(systemName: "chevron.down")
                    .font(MeshTheme.Typography.icon(size: 11, weight: .semibold))
                    .foregroundStyle(MeshTheme.Colors.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .padding(.top, 2)
    }

    private func slotRow(_ slot: WalletReceiveSlotOption, style: SlotRowStyle) -> some View {
        let isSelected = slot.index == selectedIndex

        return Button {
            onSelect(slot.index)
            withAnimation(MeshBalanceRevealAnimation.listExpand) {
                isExpanded = false
            }
        } label: {
            slotCard(slot, style: style, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityLabel("\(slot.title), \(slot.address)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func expandList() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            isExpanded = true
        }
    }

    private func toggleList() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) {
            isExpanded.toggle()
        }
    }

    private struct ExpandedFitLayout {
        let rowHeight: CGFloat
        let rowSpacing: CGFloat
        let isCompact: Bool

        func totalHeight(slotCount: Int) -> CGFloat {
            let count = max(1, slotCount)
            return CGFloat(count) * rowHeight + CGFloat(max(0, count - 1)) * rowSpacing
        }

        static func standard(slotCount: Int) -> ExpandedFitLayout {
            ExpandedFitLayout(rowHeight: 68, rowSpacing: 10, isCompact: false)
        }

        static func fitting(slotCount: Int, availableHeight: CGFloat) -> ExpandedFitLayout {
            let count = max(1, slotCount)
            let spacing: CGFloat = 5
            let totalSpacing = CGFloat(max(0, count - 1)) * spacing
            let rowHeight = max(40, (availableHeight - totalSpacing) / CGFloat(count))
            return ExpandedFitLayout(
                rowHeight: min(rowHeight, 56),
                rowSpacing: spacing,
                isCompact: true
            )
        }
    }

    private enum SlotRowStyle {
        case expanded(fit: ExpandedFitLayout)
    }

    private func slotCard(
        _ slot: WalletReceiveSlotOption,
        style: SlotRowStyle,
        isSelected: Bool
    ) -> some View {
        let isMainSlot = slot.index == 0
        let metrics = slotMetrics(for: style)

        return HStack(alignment: .top, spacing: metrics.spacing) {
            VStack(alignment: .leading, spacing: metrics.innerSpacing) {
                HStack(spacing: 8) {
                    Text(slot.title)
                        .font(metrics.titleFont)
                        .foregroundStyle(
                            isSelected
                                ? MeshTheme.Colors.textPrimary
                                : MeshTheme.Colors.textSecondary
                        )

                    if isMainSlot {
                        Text(L10n.Receive.mainBadge)
                            .font(MeshTheme.Typography.sans(size: 9, weight: .semibold))
                            .foregroundStyle(MeshTheme.Colors.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                MeshTheme.Colors.fieldFillPressed,
                                in: Capsule()
                            )
                    }
                }

                Text(ReceiveViewModel.receiveDisplayAddress(slot.address))
                    .font(metrics.addressFont)
                    .foregroundStyle(MeshTheme.Colors.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if showsBalance {
                MeshFlowAnimatedBalanceText(
                    text: slot.formattedBalance,
                    font: metrics.balanceFont,
                    color: isSelected
                        ? MeshTheme.Colors.textPrimary
                        : MeshTheme.Colors.textSecondary,
                    isPending: isLoading || slot.balanceUSDT == nil
                )
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.vertical, metrics.verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                .fill(
                    isSelected
                        ? MeshTheme.Colors.fieldFill
                        : MeshTheme.Colors.fieldFill.opacity(metrics.backgroundOpacity)
                )
        )
        .overlay {
            if showsSelectionBorder(style: style, isSelected: isSelected) {
                RoundedRectangle(cornerRadius: metrics.cornerRadius, style: .continuous)
                    .strokeBorder(MeshTheme.Colors.textTertiary.opacity(0.45), lineWidth: 1)
            }
        }
        .scaleEffect(metrics.scale, anchor: .top)
        .opacity(metrics.opacity)
        .onLongPressGesture(minimumDuration: 0.5) {
            guard slot.index > 0 else { return }
            onLongPress?(slot.index)
        }
    }

    private struct SlotMetrics {
        let titleFont: Font
        let addressFont: Font
        let balanceFont: Font
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat
        let cornerRadius: CGFloat
        let spacing: CGFloat
        let innerSpacing: CGFloat
        let scale: CGFloat
        let opacity: Double
        let backgroundOpacity: Double
    }

    private func showsSelectionBorder(style: SlotRowStyle, isSelected: Bool) -> Bool {
        isSelected
    }

    private func slotMetrics(for style: SlotRowStyle) -> SlotMetrics {
        let metrics: SlotMetrics
        switch style {
        case .expanded(let fit):
            if fit.isCompact {
                metrics = SlotMetrics(
                    titleFont: MeshTheme.Typography.sans(size: 13, weight: .semibold),
                    addressFont: MeshTheme.Typography.sans(size: 11, weight: .regular),
                    balanceFont: MeshTheme.Typography.sans(size: 12, weight: .semibold),
                    horizontalPadding: 12,
                    verticalPadding: 6,
                    cornerRadius: 12,
                    spacing: 8,
                    innerSpacing: 2,
                    scale: 1,
                    opacity: 1,
                    backgroundOpacity: 0.55
                )
            } else {
                metrics = SlotMetrics(
                    titleFont: MeshTheme.Typography.sans(size: 15, weight: .semibold),
                    addressFont: MeshTheme.Typography.caption(),
                    balanceFont: MeshTheme.Typography.sans(size: 14, weight: .semibold),
                    horizontalPadding: 14,
                    verticalPadding: 12,
                    cornerRadius: 14,
                    spacing: 10,
                    innerSpacing: 4,
                    scale: 1,
                    opacity: 1,
                    backgroundOpacity: 0.55
                )
            }
        }
        if usesOpaqueCards, case .expanded = style {
            return SlotMetrics(
                titleFont: metrics.titleFont,
                addressFont: metrics.addressFont,
                balanceFont: metrics.balanceFont,
                horizontalPadding: metrics.horizontalPadding,
                verticalPadding: metrics.verticalPadding,
                cornerRadius: metrics.cornerRadius,
                spacing: metrics.spacing,
                innerSpacing: metrics.innerSpacing,
                scale: metrics.scale,
                opacity: 1,
                backgroundOpacity: 1
            )
        }
        return metrics
    }
}

/// Compact breakdown rows for the home screen (always expanded list).
struct MeshWalletSlotBalanceBreakdownView: View {
    let slots: [WalletReceiveSlotOption]
    var balanceHidden: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            ForEach(slots) { slot in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(slot.title)
                            .font(MeshTheme.Typography.sans(size: 14, weight: .medium))
                            .foregroundStyle(MeshTheme.Colors.textSecondary)
                        if slot.index == 0 {
                            Text(L10n.Receive.mainBadge)
                                .font(MeshTheme.Typography.caption())
                                .foregroundStyle(MeshTheme.Colors.textTertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Group {
                        if balanceHidden {
                            Text("•••")
                                .font(MeshTheme.Typography.sans(size: 15, weight: .semibold))
                                .foregroundStyle(MeshTheme.Colors.textPrimary)
                        } else {
                            MeshFlowAnimatedBalanceText(
                                text: slot.formattedBalance,
                                font: MeshTheme.Typography.sans(size: 15, weight: .semibold),
                                color: MeshTheme.Colors.textPrimary,
                                isPending: slot.balanceUSDT == nil
                            )
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    MeshTheme.Colors.fieldFill.opacity(0.55),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }
        }
    }
}
