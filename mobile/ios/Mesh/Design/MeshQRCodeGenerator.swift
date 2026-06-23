import CoreImage.CIFilterBuiltins
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum MeshQRCodeGenerator {
    static func image(from string: String, dimension: CGFloat = 512) -> UIImage? {
        #if canImport(UIKit)
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(
            scaleX: dimension / output.extent.width,
            y: dimension / output.extent.height
        ))
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
        #else
        return nil
        #endif
    }
}

#if canImport(UIKit)
struct MeshQRCodeImage: View {
    let payload: String

    var body: some View {
        if let uiImage = MeshQRCodeGenerator.image(from: payload) {
            Image(uiImage: uiImage)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
        } else {
            Rectangle()
                .fill(Color.gray.opacity(0.2))
        }
    }
}
#endif
