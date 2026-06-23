import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct MeshSlideToSend: View {
    let title: String
    var isEnabled: Bool = true
    var showsPreparingActivity: Bool = false
    var usesCompactTitle: Bool = false
    let onConfirmed: () -> Void

    @State private var dragOffset: CGFloat = 0
    #if canImport(UIKit)
    @State private var confirmHaptic = UINotificationFeedbackGenerator()
    #endif

    private var trackHeight: CGFloat { MeshTheme.Metrics.buttonHeight }
    private var thumbSize: CGFloat { max(trackHeight - 12, 40) }
    private var thumbInset: CGFloat { (trackHeight - thumbSize) / 2 }

    private var usesLiquidGlass: Bool {
        MeshLiquidGlass.isSupported && isEnabled
    }

    var body: some View {
        GeometryReader { proxy in
            let trackWidth = proxy.size.width
            let maxOffset = max(trackWidth - thumbSize - thumbInset * 2, 0)

            ZStack(alignment: .leading) {
                Group {
                    if isEnabled {
                        MeshGlassCapsuleBackground()
                            .meshLiquidGlassSurface(
                                enabled: usesLiquidGlass,
                                shape: .capsule,
                                tint: MeshWalletHomeGlass.fundGlassTint
                            )
                    } else {
                        Capsule()
                            .fill(MeshTheme.Colors.surfacePressed)
                    }
                }

                Text(title)
                    .font(sliderTitleFont)
                    .foregroundStyle(sliderTitleColor)
                    .lineLimit(2)
                    .minimumScaleFactor(usesCompactTitle ? 0.68 : 0.72)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, thumbSize + thumbInset * 2)
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(false)

                Circle()
                    .fill(Color.white.opacity(isEnabled ? 0.35 : 0.22))
                    .frame(width: thumbSize, height: thumbSize)
                    .overlay {
                        if showsPreparingActivity {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(MeshTheme.Colors.textPrimary)
                                .scaleEffect(0.85)
                        } else {
                            Image(systemName: "chevron.right")
                                .font(MeshTheme.Typography.icon(size: 16, weight: .semibold))
                                .foregroundStyle(MeshTheme.Colors.textPrimary)
                        }
                    }
                    .offset(x: thumbInset + dragOffset)
                    .allowsHitTesting(false)
            }
            .contentShape(Capsule())
            .gesture(slideGesture(maxOffset: maxOffset))
            .opacity(isEnabled ? 1 : 0.55)
        }
        .meshRectangularButtonFrame()
    }

    private var sliderTitleFont: Font {
        if usesCompactTitle {
            return MeshTheme.Typography.sans(size: 13, weight: .regular)
        }
        return MeshTheme.Typography.buttonPrimary()
    }

    private var sliderTitleColor: Color {
        if usesCompactTitle {
            return MeshTheme.Colors.textPrimary.opacity(0.78)
        }
        return MeshTheme.Colors.buttonPrimaryText.opacity(0.9)
    }

    private func slideGesture(maxOffset: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                guard isEnabled else { return }
                #if canImport(UIKit)
                if dragOffset == 0 {
                    confirmHaptic.prepare()
                }
                #endif
                dragOffset = min(max(0, value.translation.width), maxOffset)
            }
            .onEnded { _ in
                guard isEnabled else { return }
                if dragOffset > maxOffset * 0.82 {
                    dragOffset = maxOffset
                    playSendConfirmHaptic()
                    onConfirmed()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        withAnimation(.easeOut(duration: 0.2)) {
                            dragOffset = 0
                        }
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        dragOffset = 0
                    }
                }
            }
    }

    private func playSendConfirmHaptic() {
        #if canImport(UIKit)
        confirmHaptic.notificationOccurred(.success)
        confirmHaptic.prepare()
        #endif
    }

}
