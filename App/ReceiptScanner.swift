import SwiftUI
import VisionKit
import Vision
import LedgerCore

/// Apple's document camera (edge detection, auto-crop). Returns the scanned pages, or [] if cancelled.
struct DocumentScanner: UIViewControllerRepresentable {
    let onFinish: ([CGImage]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }
    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([CGImage]) -> Void
        init(onFinish: @escaping ([CGImage]) -> Void) { self.onFinish = onFinish }

        func documentCameraViewController(_ c: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            onFinish((0..<scan.pageCount).compactMap { scan.imageOfPage(at: $0).cgImage })
        }
        func documentCameraViewControllerDidCancel(_ c: VNDocumentCameraViewController) { onFinish([]) }
        func documentCameraViewController(_ c: VNDocumentCameraViewController, didFailWithError error: Error) { onFinish([]) }
    }
}

/// On-device text recognition (Vision). Nothing leaves the phone.
enum ReceiptText {
    /// Text lines top to bottom across all pages.
    static func lines(in images: [CGImage]) async -> [String] {
        await Task.detached(priority: .userInitiated) {
            images.flatMap { image -> [String] in
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                try? VNImageRequestHandler(cgImage: image).perform([request])
                return (request.results ?? [])
                    .sorted { $0.boundingBox.minY > $1.boundingBox.minY } // Vision's y grows upward
                    .compactMap { $0.topCandidates(1).first?.string }
            }
        }.value
    }

    /// The sentence to put in the text box, or nil if no total could be found.
    static func sentence(from images: [CGImage]) async -> String? {
        ReceiptReader.sentence(from: await lines(in: images))
    }
}
