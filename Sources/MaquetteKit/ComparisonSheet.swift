import AppKit

// One evidence image for the vision slot: reference photo on the left, the
// four review renders in a labeled 2x2 grid on the right. The sheet is the
// only thing the vision model sees, so labels are burned into the pixels.

public enum ComparisonSheetError: Error, CustomStringConvertible {
    case encodeFailed

    public var description: String { "comparison sheet PNG encode failed" }
}

public enum ComparisonSheet {
    static let height = 768
    static let referenceWidth = 576
    static let cell = 384

    public static func compose(reference: CGImage,
                               renders: [(view: RenderView, png: Data)]) throws -> Data {
        let width = referenceWidth + cell * 2
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: width, pixelsHigh: height,
                                         bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else {
            throw ComparisonSheetError.encodeFailed
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context

        NSColor(calibratedWhite: 0.92, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()

        let referenceRect = NSRect(x: 0, y: 0, width: referenceWidth, height: height)
        draw(image: reference, fitting: referenceRect.insetBy(dx: 8, dy: 8))
        drawLabel("REFERENCE", at: NSPoint(x: 12, y: height - 34))

        // 2x2 grid, reading order: top row front, threeQuarter; bottom row side, top.
        let slots: [(RenderView, NSRect)] = [
            (.front, NSRect(x: referenceWidth, y: cell, width: cell, height: cell)),
            (.threeQuarter, NSRect(x: referenceWidth + cell, y: cell, width: cell, height: cell)),
            (.side, NSRect(x: referenceWidth, y: 0, width: cell, height: cell)),
            (.top, NSRect(x: referenceWidth + cell, y: 0, width: cell, height: cell)),
        ]
        for (view, rect) in slots {
            guard let png = renders.first(where: { $0.view == view })?.png,
                  let image = NSBitmapImageRep(data: png)?.cgImage else { continue }
            draw(image: image, fitting: rect.insetBy(dx: 4, dy: 4))
            drawLabel("RENDER \(view.rawValue)",
                      at: NSPoint(x: rect.minX + 10, y: rect.maxY - 30))
        }

        NSGraphicsContext.restoreGraphicsState()

        guard let png = rep.representation(using: .png, properties: [:]) else {
            throw ComparisonSheetError.encodeFailed
        }
        return png
    }

    private static func draw(image: CGImage, fitting rect: NSRect) {
        let size = NSSize(width: image.width, height: image.height)
        let scale = min(rect.width / size.width, rect.height / size.height)
        let fitted = NSRect(x: rect.midX - size.width * scale / 2,
                            y: rect.midY - size.height * scale / 2,
                            width: size.width * scale,
                            height: size.height * scale)
        NSImage(cgImage: image, size: size).draw(in: fitted)
    }

    private static func drawLabel(_ text: String, at point: NSPoint) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 18),
            .foregroundColor: NSColor.black,
        ]
        let string = NSAttributedString(string: text, attributes: attributes)
        let size = string.size()
        let pad: CGFloat = 4
        NSColor(calibratedWhite: 1, alpha: 0.75).setFill()
        NSRect(x: point.x - pad, y: point.y - pad,
               width: size.width + pad * 2, height: size.height + pad * 2).fill()
        string.draw(at: point)
    }
}
