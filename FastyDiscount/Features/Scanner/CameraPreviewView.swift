import AVFoundation
import SwiftUI
import UIKit

// MARK: - CameraPreviewView

/// A `UIViewRepresentable` wrapper around `AVCaptureVideoPreviewLayer`
/// that displays the live camera feed from an `AVCaptureSession`.
///
/// The preview layer automatically resizes to fill the available SwiftUI frame
/// and uses `.resizeAspectFill` to avoid letterboxing.
struct CameraPreviewView: UIViewRepresentable {

    /// The capture session whose output should be displayed.
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        // Session binding is set once in makeUIView; no updates needed.
    }
}

// MARK: - PreviewUIView

/// A plain `UIView` whose `layerClass` is `AVCaptureVideoPreviewLayer`,
/// ensuring the preview layer automatically resizes with Auto Layout.
final class PreviewUIView: UIView {

    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    /// Typed accessor for the layer as `AVCaptureVideoPreviewLayer`.
    var previewLayer: AVCaptureVideoPreviewLayer {
        // swiftlint:disable:next force_cast
        layer as! AVCaptureVideoPreviewLayer
    }
}
