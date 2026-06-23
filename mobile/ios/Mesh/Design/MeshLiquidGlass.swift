import SwiftUI

enum MeshLiquidGlassButtonRole {
    case regular
    case prominent
}

enum MeshLiquidGlassShape {
    case capsule
    case circle
    case roundedRectangle(radius: CGFloat)
}

enum MeshLiquidGlass {
    static var isSupported: Bool {
        if #available(iOS 26.0, *) {
            return true
        }
        return false
    }
}

extension View {
    /// Full-width capsule actions at `MeshTheme.Metrics.buttonHeight` (56pt).
    /// Apply after `.meshLiquidGlassButton` — system glass styles otherwise use a smaller default height.
    func meshRectangularButtonFrame() -> some View {
        frame(maxWidth: .infinity)
            .frame(height: MeshTheme.Metrics.buttonHeight)
    }

    /// Standard Apple Liquid Glass on `Button` — only when `enabled` (disabled keeps plain / custom fill).
    @ViewBuilder
    func meshLiquidGlassButton(
        enabled: Bool = true,
        role: MeshLiquidGlassButtonRole = .regular,
        shape: MeshLiquidGlassShape = .capsule,
        tint: Color? = nil
    ) -> some View {
        if #available(iOS 26.0, *), enabled {
            meshLiquidGlassButtonStyle(role: role, shape: shape, tint: tint)
        } else {
            buttonStyle(.plain)
        }
    }

    /// Liquid Glass material on a non-button surface (slide track, icon disc).
    @ViewBuilder
    func meshLiquidGlassSurface(
        enabled: Bool = true,
        shape: MeshLiquidGlassShape = .capsule,
        tint: Color? = nil
    ) -> some View {
        if #available(iOS 26.0, *), enabled {
            meshLiquidGlassEffect(shape: shape, tint: tint)
        } else {
            self
        }
    }

}

@available(iOS 26.0, *)
private extension View {
    @ViewBuilder
    func meshLiquidGlassButtonStyle(
        role: MeshLiquidGlassButtonRole,
        shape: MeshLiquidGlassShape,
        tint: Color?
    ) -> some View {
        switch role {
        case .prominent:
            switch shape {
            case .capsule:
                tintedIfNeeded(tint) {
                    buttonStyle(.glassProminent)
                        .buttonBorderShape(.capsule)
                        .buttonSizing(.flexible)
                }
            case .circle:
                tintedIfNeeded(tint) {
                    buttonStyle(.glassProminent).buttonBorderShape(.circle)
                }
            case .roundedRectangle(let radius):
                tintedIfNeeded(tint) {
                    buttonStyle(.glassProminent)
                        .buttonBorderShape(.roundedRectangle(radius: radius))
                        .buttonSizing(.flexible)
                }
            }
        case .regular:
            switch shape {
            case .capsule:
                tintedIfNeeded(tint) {
                    buttonStyle(.glass)
                        .buttonBorderShape(.capsule)
                        .buttonSizing(.flexible)
                }
            case .circle:
                tintedIfNeeded(tint) {
                    buttonStyle(.glass).buttonBorderShape(.circle)
                }
            case .roundedRectangle(let radius):
                tintedIfNeeded(tint) {
                    buttonStyle(.glass)
                        .buttonBorderShape(.roundedRectangle(radius: radius))
                        .buttonSizing(.flexible)
                }
            }
        }
    }

    @ViewBuilder
    func meshLiquidGlassEffect(shape: MeshLiquidGlassShape, tint: Color?) -> some View {
        let material = meshGlassMaterial(tint: tint)
        switch shape {
        case .capsule:
            glassEffect(material, in: .capsule)
        case .circle:
            glassEffect(material, in: .circle)
        case .roundedRectangle(let radius):
            glassEffect(material, in: .rect(cornerRadius: radius))
        }
    }

    func meshGlassMaterial(tint: Color?) -> Glass {
        if let tint {
            return .regular.tint(tint).interactive()
        }
        return .regular.interactive()
    }

    @ViewBuilder
    func tintedIfNeeded(_ tint: Color?, @ViewBuilder content: () -> some View) -> some View {
        if let tint {
            content().tint(tint)
        } else {
            content()
        }
    }
}
