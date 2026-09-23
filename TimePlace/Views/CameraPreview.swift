import SwiftUI
import AVFoundation

struct CameraPreview: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer?

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()

        if let previewLayer {
            view.setPreviewLayer(previewLayer)
        }

        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        // IMPORTANT:
        // A preview layer should stay permanently attached to its
        // corresponding UIView. Do not swap preview layers between views.
        if uiView.previewLayer !== previewLayer {
            uiView.setPreviewLayer(previewLayer)
        }

        uiView.setNeedsLayout()
    }
}

final class PreviewUIView: UIView {

    private(set) var previewLayer: AVCaptureVideoPreviewLayer?

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .black
        clipsToBounds = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)

        backgroundColor = .black
        clipsToBounds = true
    }

    func setPreviewLayer(_ newLayer: AVCaptureVideoPreviewLayer?) {
        guard previewLayer !== newLayer else {
            return
        }

        previewLayer?.removeFromSuperlayer()

        previewLayer = newLayer

        guard let newLayer else {
            return
        }

        newLayer.videoGravity = .resizeAspectFill
        newLayer.frame = bounds

        layer.insertSublayer(newLayer, at: 0)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        previewLayer?.frame = bounds
    }

    deinit {
        previewLayer?.removeFromSuperlayer()
    }
}
