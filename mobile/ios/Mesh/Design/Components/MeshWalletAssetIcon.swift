import SwiftUI

enum MeshWalletIcons {
    static let wallet = "Wallet"
}

/// Template wallet glyph from `Assets.xcassets/Wallet`.
struct MeshWalletAssetIcon: View {
    var size: CGFloat = 20
    var color: Color = MeshTheme.Colors.textPrimary

    var body: some View {
        Image(MeshWalletIcons.wallet)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(color)
    }
}
