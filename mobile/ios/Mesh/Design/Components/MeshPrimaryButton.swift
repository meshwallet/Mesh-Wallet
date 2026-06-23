import SwiftUI

struct MeshPrimaryButton: View {
    let title: String
    var icon: String? = nil
    var assetIcon: String? = nil
    var isEnabled: Bool = true
    var usesLiquidGlass: Bool? = nil
    var titleColor: Color = MeshTheme.Colors.buttonPrimaryText
    let action: () -> Void

    private var appliesLiquidGlass: Bool {
        if let usesLiquidGlass {
            return usesLiquidGlass && isEnabled
        }
        return MeshLiquidGlass.isSupported && isEnabled
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let assetIcon {
                    Image(assetIcon)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 18, height: 18)
                } else if let icon {
                    Image(systemName: icon)
                        .font(MeshTheme.Typography.icon(size: 18, weight: .medium))
                }
                Text(title)
                    .font(MeshTheme.Typography.buttonPrimary())
            }
            .foregroundStyle(isEnabled ? titleColor : MeshTheme.Colors.textTertiary)
            .frame(maxWidth: .infinity)
            .frame(height: MeshTheme.Metrics.buttonHeight)
            .background {
                if isEnabled {
                    MeshGlassCapsuleBackground()
                        .meshLiquidGlassSurface(
                            enabled: appliesLiquidGlass,
                            shape: .capsule,
                            tint: MeshWalletHomeGlass.fundGlassTint
                        )
                } else {
                    Capsule()
                        .fill(MeshTheme.Colors.surfacePressed)
                }
            }
        }
        .buttonStyle(MeshGlassCircleButtonStyle())
        .meshRectangularButtonFrame()
        .disabled(!isEnabled)
    }
}
