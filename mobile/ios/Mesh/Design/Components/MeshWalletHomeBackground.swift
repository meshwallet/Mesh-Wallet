import SwiftUI

enum MeshWalletHomeColors {
    static let topPurple = Color(hex: 0x9688AD)
    /// Selected pill on filter bar (mockup).
    static let filterPillSelected = Color(hex: 0xA89BB5)
    /// Near-black with a trace of hero purple — list / sheet bottoms (#0D0C14).
    static let bottomSurface = Color(hex: 0x0D0C14)

    static func bottomVeil(_ opacity: Double) -> Color {
        bottomSurface.opacity(opacity)
    }

    static var heroScrollFadeStops: [Gradient.Stop] {
        [
            .init(color: Color.clear, location: 0),
            .init(color: Color.clear, location: 0.18),
            .init(color: bottomVeil(0.04), location: 0.28),
            .init(color: bottomVeil(0.10), location: 0.38),
            .init(color: bottomVeil(0.18), location: 0.48),
            .init(color: bottomVeil(0.28), location: 0.58),
            .init(color: bottomVeil(0.40), location: 0.67),
            .init(color: bottomVeil(0.54), location: 0.75),
            .init(color: bottomVeil(0.68), location: 0.82),
            .init(color: bottomVeil(0.82), location: 0.89),
            .init(color: bottomVeil(0.90), location: 0.95),
            .init(color: bottomSurface, location: 1),
        ]
    }

    static var heroScrollFadeGradient: LinearGradient {
        LinearGradient(
            stops: heroScrollFadeStops,
            startPoint: .top,
            endPoint: .bottom
        )
    }

    static var sheetBackgroundStops: [Gradient.Stop] {
        [
            .init(color: topPurple.opacity(0.52), location: 0),
            .init(color: topPurple.opacity(0.30), location: 0.32),
            .init(color: bottomVeil(0.72), location: 0.62),
            .init(color: bottomVeil(0.90), location: 0.86),
            .init(color: bottomSurface, location: 1),
        ]
    }

    static var sheetBackgroundGradient: LinearGradient {
        LinearGradient(
            stops: sheetBackgroundStops,
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Send to self sheet — much darker purple/black at the top.
    static var sendToSelfSheetBackgroundStops: [Gradient.Stop] {
        [
            .init(color: bottomSurface, location: 0),
            .init(color: bottomVeil(0.98), location: 0.14),
            .init(color: bottomVeil(0.94), location: 0.28),
            .init(color: bottomVeil(0.86), location: 0.42),
            .init(color: topPurple.opacity(0.18), location: 0.58),
            .init(color: bottomVeil(0.92), location: 0.78),
            .init(color: bottomSurface, location: 1),
        ]
    }

    static var sendToSelfSheetBackgroundGradient: LinearGradient {
        LinearGradient(
            stops: sendToSelfSheetBackgroundStops,
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// Hero backdrop — solid purple.
struct MeshWalletHomeHeroBackdrop: View {
    let height: CGFloat

    var body: some View {
        MeshWalletHomeColors.topPurple
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
    }
}

/// Purple at top → black at bottom (hero under UI).
struct MeshWalletHomeHeroScrollFade: View {
    let height: CGFloat

    var body: some View {
        MeshWalletHomeColors.heroScrollFadeGradient
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .allowsHitTesting(false)
    }
}

/// Fixed top atmosphere — purple fading downward.
struct MeshWalletHomeTopAtmosphere: View {
    let height: CGFloat

    var body: some View {
        LinearGradient(
            stops: [
                .init(color: MeshWalletHomeColors.topPurple, location: 0),
                .init(color: MeshWalletHomeColors.topPurple, location: 0.38),
                .init(color: MeshWalletHomeColors.topPurple.opacity(0.94), location: 0.52),
                .init(color: MeshWalletHomeColors.topPurple.opacity(0.78), location: 0.64),
                .init(color: MeshWalletHomeColors.topPurple.opacity(0.52), location: 0.76),
                .init(color: MeshWalletHomeColors.topPurple.opacity(0.24), location: 0.88),
                .init(color: Color.clear, location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: height)
        .frame(maxWidth: .infinity, alignment: .top)
        .allowsHitTesting(false)
    }
}

/// Fixed viewport fill — solid purple.
struct MeshWalletHomeViewportBackground: View {
    var body: some View {
        MeshWalletHomeColors.topPurple
            .ignoresSafeArea()
    }
}

/// Wallet picker, transaction detail — purple (top) → black (bottom).
struct MeshSelectWalletSheetBackground: View {
    var gradient: LinearGradient = MeshWalletHomeColors.sheetBackgroundGradient

    var body: some View {
        ZStack {
            MeshWalletHomeColors.bottomSurface
            gradient
        }
        .ignoresSafeArea()
    }
}
