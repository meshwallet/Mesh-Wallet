import SwiftUI

struct MeshSecondaryButton: View {
    @Environment(\.meshScreenFooterButtons) private var meshScreenFooterButtons

    let title: String
    var icon: String? = nil
    var isEnabled: Bool = true
    var usesLiquidGlass: Bool? = nil
    var style: Style = .outline
    let action: () -> Void

    enum Style {
        /// Hairline capsule on black (welcome restore).
        case outline
        /// Filled pill — Paste / Scan QR (Send reference).
        case field
    }

    private var appliesLiquidGlass: Bool {
        if meshScreenFooterButtons { return false }
        if let usesLiquidGlass {
            return usesLiquidGlass && isEnabled
        }
        return MeshLiquidGlass.isSupported && isEnabled
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(MeshTheme.Typography.icon(size: 18, weight: .medium))
                }
                Text(title)
                    .font(MeshTheme.Typography.button())
            }
            .foregroundStyle(isEnabled ? MeshTheme.Colors.buttonSecondaryText : MeshTheme.Colors.textTertiary)
            .frame(maxWidth: .infinity)
            .frame(height: MeshTheme.Metrics.buttonHeight)
            .background {
                if !appliesLiquidGlass {
                    Capsule().fill(fieldBackgroundColor)
                }
            }
            .overlay {
                if !appliesLiquidGlass, style == .outline {
                    Capsule()
                        .stroke(
                            isEnabled ? MeshTheme.Colors.border : MeshTheme.Colors.borderSubtle,
                            lineWidth: 1
                        )
                }
            }
        }
        .meshLiquidGlassButton(enabled: appliesLiquidGlass, role: .regular, shape: .capsule)
        .meshRectangularButtonFrame()
        .disabled(!isEnabled)
    }

    private var fieldBackgroundColor: Color {
        switch style {
        case .outline:
            return .clear
        case .field:
            return isEnabled ? MeshTheme.Colors.fieldFill : MeshTheme.Colors.fieldFillPressed
        }
    }
}
