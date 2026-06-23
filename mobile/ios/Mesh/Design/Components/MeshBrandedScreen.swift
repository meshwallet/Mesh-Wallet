import SwiftUI

/// Black background and centered app icon — launch splash (matches `LaunchScreen.storyboard`).
struct MeshBrandedScreen: View {
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                MeshTheme.Colors.background

                Image("IconPng")
                    .resizable()
                    .scaledToFit()
                    .frame(width: geometry.size.width * 0.5)
                    .position(
                        x: geometry.size.width * 0.5,
                        y: geometry.size.height * 0.5
                    )
                    .accessibilityHidden(true)
            }
        }
        .ignoresSafeArea()
    }
}
