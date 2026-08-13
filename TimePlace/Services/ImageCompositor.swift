import UIKit

/// Draws the small "corner" photo on top of the full-size "main" photo,
/// matching what's shown on screen, so a single flattened image gets uploaded.
enum ImageCompositor {
    static func composite(main: UIImage, corner: UIImage) -> UIImage {
        let size = main.size
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { _ in
            main.draw(in: CGRect(origin: .zero, size: size))

            let cornerWidth = size.width * 0.32
            let cornerHeight = cornerWidth * (corner.size.height / corner.size.width)
            let margin = size.width * 0.04
            let cornerRect = CGRect(
                x: size.width - cornerWidth - margin,
                y: size.height - cornerHeight - margin,
                width: cornerWidth,
                height: cornerHeight
            )

            let clipPath = UIBezierPath(roundedRect: cornerRect, cornerRadius: 16)
            clipPath.addClip()
            corner.draw(in: cornerRect)

            let borderPath = UIBezierPath(roundedRect: cornerRect, cornerRadius: 16)
            UIColor.white.setStroke()
            borderPath.lineWidth = 3
            borderPath.stroke()
        }
    }
}
