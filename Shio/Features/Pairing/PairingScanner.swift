import SwiftUI
import VisionKit

/// Thin SwiftUI wrapper over `DataScannerViewController` that surfaces the
/// first QR payload it reads. Camera-only — unavailable on the simulator and
/// on devices without scanning support; callers should check
/// `PairingScanner.isSupported` and fall back to manual entry.
struct PairingScanner: UIViewControllerRepresentable {

    /// Called with the raw decoded string of the first QR seen.
    var onScan: (String) -> Void

    /// True only where DataScanner can actually run (real device, camera,
    /// Neural Engine). False on the simulator → show manual entry instead.
    static var isSupported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        try? scanner.startScanning()
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        private let onScan: (String) -> Void
        /// Guard so we fire `onScan` exactly once per presentation.
        private var fired = false

        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            handle(addedItems)
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            handle([item])
        }

        private func handle(_ items: [RecognizedItem]) {
            guard !fired else { return }
            for case let .barcode(barcode) in items {
                if let value = barcode.payloadStringValue {
                    fired = true
                    onScan(value)
                    return
                }
            }
        }
    }
}
