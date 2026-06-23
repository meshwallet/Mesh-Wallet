import SwiftUI

/// Pure black — optional single soft vertical accent (minimal).
struct MeshAmbientBackground: View {
    var body: some View {
        ZStack {
            MeshTheme.Colors.background

            Rectangle()
                .fill(Color.white.opacity(0.04))
                .frame(width: 1)
                .blur(radius: 40)
                .opacity(0.6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
