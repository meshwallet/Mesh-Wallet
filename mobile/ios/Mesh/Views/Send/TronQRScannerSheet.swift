import SwiftUI

struct TronQRScannerSheet: View {
    let onScanned: (String) -> Void

    var body: some View {
        #if canImport(VisionKit) && canImport(UIKit)
        if #available(iOS 16.0, *) {
            TronQRScannerContent(onScanned: onScanned)
        } else {
            unsupportedView
        }
        #else
        unsupportedView
        #endif
    }

    private var unsupportedView: some View {
        Text("QR scanning is not available on this device.")
            .font(MeshTheme.Typography.secondary())
            .foregroundStyle(MeshTheme.Colors.textSecondary)
            .padding()
    }
}

#if canImport(VisionKit) && canImport(UIKit)
import Vision
import VisionKit
import UIKit

@available(iOS 16.0, *)
private struct TronQRScannerContent: View {
    let onScanned: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            QRScannerRepresentable(onScanned: onScanned)
                .ignoresSafeArea()
                .navigationTitle("Scan QR")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .buttonStyle(.plain)
                    }
                }
        }
        .preferredColorScheme(.dark)
    }
}

@available(iOS 16.0, *)
private struct QRScannerRepresentable: UIViewControllerRepresentable {
    let onScanned: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        guard !context.coordinator.didStart else { return }
        context.coordinator.didStart = true
        try? uiViewController.startScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScanned: onScanned)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScanned: (String) -> Void
        var didStart = false

        init(onScanned: @escaping (String) -> Void) {
            self.onScanned = onScanned
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            extract(item)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard let item = addedItems.first else { return }
            extract(item)
        }

        private func extract(_ item: RecognizedItem) {
            if case .barcode(let barcode) = item, let value = barcode.payloadStringValue {
                onScanned(value)
            }
        }
    }
}
#endif
