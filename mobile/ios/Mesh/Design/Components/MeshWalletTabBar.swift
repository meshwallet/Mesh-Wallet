import SwiftUI

enum MeshWalletTab: Hashable {
    case wallet
    case links
}

struct MeshWalletTabBar: View {
    @Binding var selection: MeshWalletTab

    var body: some View {
        HStack(spacing: 4) {
            tabItem(.wallet, assetIcon: MeshWalletIcons.wallet, title: "Wallet")
            tabItem(.links, icon: "link", title: "Links")
        }
        .padding(4)
        .background {
            if !MeshLiquidGlass.isSupported {
                Capsule().fill(MeshTheme.Colors.tabBarFill)
            }
        }
        .overlay {
            if !MeshLiquidGlass.isSupported {
                Capsule()
                    .stroke(MeshTheme.Colors.borderSubtle, lineWidth: 1)
            }
        }
        .meshLiquidGlassSurface(enabled: MeshLiquidGlass.isSupported, shape: .capsule)
    }

    private func tabItem(
        _ tab: MeshWalletTab,
        assetIcon: String? = nil,
        icon: String? = nil,
        title: String
    ) -> some View {
        let isSelected = selection == tab
        let usesGlass = MeshLiquidGlass.isSupported && isSelected

        return Button {
            selection = tab
        } label: {
            VStack(spacing: 4) {
                Group {
                    if let assetIcon {
                        Image(assetIcon)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                    } else if let icon {
                        Image(systemName: icon)
                            .font(MeshTheme.Typography.icon(size: 18, weight: .light))
                    }
                }
                Text(title)
                    .font(MeshTheme.Typography.sans(size: 12, weight: .light))
            }
            .foregroundStyle(isSelected ? MeshTheme.Colors.textPrimary : MeshTheme.Colors.textTertiary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background {
                if !usesGlass, isSelected {
                    Capsule()
                        .fill(MeshTheme.Colors.tabBarActiveFill)
                }
            }
        }
        .meshLiquidGlassButton(enabled: isSelected, role: .regular, shape: .capsule)
    }
}
