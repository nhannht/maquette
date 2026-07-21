import Foundation
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers
import Vision

// Subject lift: isolate the foreground subject so the vision judge compares
// models against the object, not the background. Uses Vision's built-in
// foreground instance mask - fully on-device, no ML weights to ship.

public enum SubjectLiftError: Error, CustomStringConvertible {
    case imageLoad(String)
    case noSubject
    case export(String)

    public var description: String {
        switch self {
        case .imageLoad(let m): return "image load failed: \(m)"
        case .noSubject: return "Vision found no foreground subject in the image"
        case .export(let m): return "export failed: \(m)"
        }
    }
}

public struct MaskResult {
    public let width: Int
    public let height: Int
    public let values: [Float] // row-major, 0..1, same size as input photo

    public init(width: Int, height: Int, values: [Float]) {
        self.width = width
        self.height = height
        self.values = values
    }
}

public func subjectMask(for image: CGImage) throws -> MaskResult {
    let request = VNGenerateForegroundInstanceMaskRequest()
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try handler.perform([request])
    guard let obs = request.results?.first else { throw SubjectLiftError.noSubject }
    let buffer = try obs.generateScaledMaskForImage(forInstances: obs.allInstances, from: handler)
    return try readFloatBuffer(buffer)
}

public func readFloatBuffer(_ buffer: CVPixelBuffer) throws -> MaskResult {
    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    let width = CVPixelBufferGetWidth(buffer)
    let height = CVPixelBufferGetHeight(buffer)
    let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
    guard let base = CVPixelBufferGetBaseAddress(buffer) else {
        throw SubjectLiftError.export("mask buffer has no base address")
    }
    var values = [Float](repeating: 0, count: width * height)
    let format = CVPixelBufferGetPixelFormatType(buffer)
    switch format {
    case kCVPixelFormatType_OneComponent32Float:
        for y in 0..<height {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float.self)
            for x in 0..<width { values[y * width + x] = row[x] }
        }
    case kCVPixelFormatType_OneComponent16Half:
        for y in 0..<height {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt16.self)
            for x in 0..<width { values[y * width + x] = Float(Float16(bitPattern: row[x])) }
        }
    case kCVPixelFormatType_OneComponent8:
        for y in 0..<height {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width { values[y * width + x] = Float(row[x]) / 255.0 }
        }
    default:
        throw SubjectLiftError.export("unsupported pixel format \(format)")
    }
    return MaskResult(width: width, height: height, values: values)
}

/// Photo with background removed (subject cutout with alpha), for eyeballing mask quality.
public func saveCutout(photo: CGImage, mask: MaskResult, to path: String) throws {
    let maskCG = try grayImage(values: mask.values, width: mask.width, height: mask.height)
    let ciPhoto = CIImage(cgImage: photo)
    let ciMask = CIImage(cgImage: maskCG)
    guard let filter = CIFilter(name: "CIBlendWithMask") else {
        throw SubjectLiftError.export("CIBlendWithMask unavailable")
    }
    filter.setValue(ciPhoto, forKey: kCIInputImageKey)
    filter.setValue(CIImage.empty(), forKey: kCIInputBackgroundImageKey)
    filter.setValue(ciMask, forKey: kCIInputMaskImageKey)
    guard let outImage = filter.outputImage else { throw SubjectLiftError.export("cutout filter failed") }
    let ctx = CIContext()
    guard let cg = ctx.createCGImage(outImage, from: CGRect(x: 0, y: 0, width: photo.width, height: photo.height)) else {
        throw SubjectLiftError.export("cutout render failed")
    }
    try savePNG(cg, to: path)
}

public func loadCGImage(_ path: String) throws -> CGImage {
    let url = URL(fileURLWithPath: path)
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        throw SubjectLiftError.imageLoad(path)
    }
    return img
}

public func savePNG(_ image: CGImage, to path: String) throws {
    let url = URL(fileURLWithPath: path)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw SubjectLiftError.export("cannot create PNG destination \(path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else {
        throw SubjectLiftError.export("cannot finalize PNG \(path)")
    }
}

/// Build an 8-bit grayscale CGImage from normalized [0,1] float values.
public func grayImage(values: [Float], width: Int, height: Int) throws -> CGImage {
    var bytes = [UInt8](repeating: 0, count: width * height)
    for i in 0..<(width * height) {
        bytes[i] = UInt8(max(0, min(255, values[i] * 255)))
    }
    let data = Data(bytes)
    guard let provider = CGDataProvider(data: data as CFData),
          let img = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8,
                            bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false,
                            intent: .defaultIntent) else {
        throw SubjectLiftError.export("cannot build grayscale image")
    }
    return img
}
