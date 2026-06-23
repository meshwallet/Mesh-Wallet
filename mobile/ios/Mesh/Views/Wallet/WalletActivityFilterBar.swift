import SwiftUI

enum WalletActivityFilter: String, CaseIterable, Identifiable {
    case all
    case received
    case sent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return L10n.Wallet.filterAll
        case .received: return L10n.Wallet.filterReceived
        case .sent: return L10n.Wallet.filterSent
        }
    }
}

struct WalletActivityFilterBar: View {
    enum Style {
        case underline
        case pill
    }

    @Binding var selection: WalletActivityFilter
    var style: Style = .underline
    var showsSearch: Bool = false
    var onSearch: (() -> Void)?

    var body: some View {
        switch style {
        case .underline:
            underlineBar
        case .pill:
            pillRow
        }
    }

    private var underlineBar: some View {
        HStack(spacing: 24) {
            ForEach(WalletActivityFilter.allCases) { filter in
                underlineTab(filter)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var pillRow: some View {
        HStack(spacing: 10) {
            pillBar
                .frame(maxWidth: .infinity)

            if showsSearch {
                searchButton
            }
        }
    }

    private var pillBar: some View {
        HStack(spacing: 0) {
            ForEach(WalletActivityFilter.allCases) { filter in
                pillTab(filter)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(4)
        .frame(height: 48)
        .background {
            Capsule()
                .fill(MeshTheme.Colors.homeCircleButtonFill)
                .overlay {
                    Capsule()
                        .stroke(MeshTheme.Colors.homeCircleButtonStroke, lineWidth: 1)
                }
                .meshLiquidGlassSurface(enabled: MeshLiquidGlass.isSupported, shape: .capsule)
        }
    }

    private var searchButton: some View {
        Button {
            onSearch?()
        } label: {
            Image(systemName: "magnifyingglass")
                .font(MeshTheme.Typography.icon(size: 17, weight: .light))
                .foregroundStyle(MeshTheme.Colors.homeChromeIcon)
                .frame(width: 48, height: 48)
                .background {
                    Circle()
                        .fill(MeshTheme.Colors.homeCircleButtonFill)
                        .overlay {
                            Circle()
                                .stroke(MeshTheme.Colors.homeCircleButtonStroke, lineWidth: 1)
                        }
                        .meshLiquidGlassSurface(enabled: MeshLiquidGlass.isSupported, shape: .circle)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search transactions")
    }

    private func underlineTab(_ filter: WalletActivityFilter) -> some View {
        let isSelected = selection == filter

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selection = filter
            }
        } label: {
            VStack(spacing: 8) {
                Text(filter.title)
                    .font(MeshTheme.Typography.sans(size: 15, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(isSelected ? MeshTheme.Colors.homeTextPrimary : MeshTheme.Colors.homeTextSecondary.opacity(0.75))

                Rectangle()
                    .fill(isSelected ? MeshTheme.Colors.homeTextPrimary : Color.clear)
                    .frame(height: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func pillTab(_ filter: WalletActivityFilter) -> some View {
        let isSelected = selection == filter

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selection = filter
            }
        } label: {
            Text(filter.title)
                .font(MeshTheme.Typography.sans(size: 14, weight: isSelected ? .medium : .regular))
                .foregroundStyle(isSelected ? MeshTheme.Colors.homeTextPrimary : MeshTheme.Colors.homeTextSecondary)
                .frame(maxWidth: .infinity, minHeight: 40)
                .contentShape(Capsule())
                .background {
                    if isSelected {
                        Capsule()
                            .fill(MeshWalletHomeColors.filterPillSelected.opacity(0.55))
                    }
                }
        }
        .buttonStyle(.plain)
    }
}
