import CoreGraphics
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum MeshBalanceFontFit {
    /// Shrinks `baseSize` so `text` fits `maxWidth` (Geist semibold measurement).
    static func fittedFontSize(
        text: String,
        baseSize: CGFloat,
        maxWidth: CGFloat,
        minScale: CGFloat = 0.38,
        weight: Font.Weight = .semibold
    ) -> CGFloat {
        guard maxWidth > 0, !text.isEmpty else { return baseSize }
        let measured = measureWidth(text, fontSize: baseSize, weight: weight)
        guard measured > maxWidth else { return baseSize }
        let scaled = baseSize * maxWidth / measured
        return max(baseSize * minScale, scaled)
    }

    static func measureWidth(
        _ text: String,
        fontSize: CGFloat,
        weight: Font.Weight = .semibold
    ) -> CGFloat {
        #if canImport(UIKit)
        let font = MeshFont.uiFont(size: fontSize, weight: weight)
        let size = (text as NSString).size(withAttributes: [.font: font])
        return ceil(size.width)
        #else
        return CGFloat(text.count) * fontSize * 0.56
        #endif
    }
}
