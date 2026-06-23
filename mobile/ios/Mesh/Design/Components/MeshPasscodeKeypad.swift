import SwiftUI

struct MeshPasscodeDots: View {
    let filledCount: Int
    let total: Int
    var hasError: Bool = false

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)

            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .fill(dotFill(for: index))
                    .frame(
                        width: MeshTheme.Metrics.passcodeDotSize,
                        height: MeshTheme.Metrics.passcodeDotSize
                    )

                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity)
        .animation(.easeOut(duration: 0.15), value: filledCount)
        .animation(.easeOut(duration: 0.15), value: hasError)
    }

    private func dotFill(for index: Int) -> Color {
        if hasError {
            return Color.orange.opacity(0.85)
        }
        return index < filledCount
            ? MeshTheme.Colors.textPrimary
            : MeshTheme.Colors.textTertiary.opacity(0.45)
    }
}

struct MeshPasscodeKeypad: View {
    let onDigit: (Int) -> Void
    let onDelete: () -> Void

    private let layout: [[Key?]] = [
        [.digit(1), .digit(2), .digit(3)],
        [.digit(4), .digit(5), .digit(6)],
        [.digit(7), .digit(8), .digit(9)],
        [nil, .digit(0), .delete]
    ]

    var body: some View {
        VStack(spacing: 12) {
            ForEach(0..<layout.count, id: \.self) { row in
                HStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { column in
                        if let key = layout[row][column] {
                            keyButton(key)
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func keyButton(_ key: Key) -> some View {
        switch key {
        case .digit(let value):
            Button {
                onDigit(value)
            } label: {
                VStack(spacing: 2) {
                    Text("\(value)")
                        .font(MeshTheme.Typography.sans(size: 24, weight: .regular))
                        .foregroundStyle(MeshTheme.Colors.textPrimary)
                    if let letters = key.letters {
                        Text(letters)
                            .font(MeshTheme.Typography.sans(size: 10, weight: .medium))
                            .foregroundStyle(MeshTheme.Colors.textTertiary)
                            .tracking(1.2)
                    } else {
                        Text(" ")
                            .font(MeshTheme.Typography.sans(size: 10, weight: .medium))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(MeshTheme.Colors.fieldFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(MeshRowButtonStyle())

        case .delete:
            Button(action: onDelete) {
                Image(systemName: "delete.left")
                    .font(MeshTheme.Typography.icon(size: 22, weight: .regular))
                    .foregroundStyle(MeshTheme.Colors.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(MeshTheme.Colors.fieldFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(MeshRowButtonStyle())
        }
    }

    private enum Key {
        case digit(Int)
        case delete

        var letters: String? {
            guard case .digit(let value) = self else { return nil }
            switch value {
            case 2: return "ABC"
            case 3: return "DEF"
            case 4: return "GHI"
            case 5: return "JKL"
            case 6: return "MNO"
            case 7: return "PQRS"
            case 8: return "TUV"
            case 9: return "WXYZ"
            default: return nil
            }
        }
    }
}

/// Small app icon shown above passcode entry UI.
struct MeshPasscodeBrandMark: View {
    var height: CGFloat = 40

    var body: some View {
        Image("IconPng")
            .resizable()
            .scaledToFit()
            .frame(height: height)
            .accessibilityLabel(L10n.Welcome.brand)
    }
}

/// Shared layout: optional top bar → IconPng → passcode body (all entry screens).
struct MeshPasscodeEntryLayout<Header: View, Content: View>: View {
    private let header: Header
    private let content: Content

    init(
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) {
        self.header = header()
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            MeshPasscodeBrandMark()
                .padding(.top, 12)
                .padding(.bottom, 4)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

extension MeshPasscodeEntryLayout where Header == EmptyView {
    init(@ViewBuilder content: () -> Content) {
        self.header = EmptyView()
        self.content = content()
    }
}
