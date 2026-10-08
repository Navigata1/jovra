import Accelerate
import CoreGraphics
import CoreVideo
import Foundation

public enum LumaPlaneError: Error, Equatable {
    case unsupportedPixelFormat(OSType)
    case lockFailed
    case drawFailed
}

/// The luma samples of one decoded frame, row-major, in native code values (8- or 10-bit). Samples are held
/// as `Float` so Accelerate can sum them; every value is a small integer, so every sum here is exact.
public struct LumaPlane: Sendable {
    public let width: Int
    public let height: Int
    public let bitDepth: Int
    private let samples: [Float]

    public init(width: Int, height: Int, bitDepth: Int, samples: [UInt16]) {
        precondition(samples.count == width * height, "one sample per pixel")
        self.init(width: width, height: height, bitDepth: bitDepth, floats: samples.map(Float.init))
    }

    private init(width: Int, height: Int, bitDepth: Int, floats: [Float]) {
        self.width = width
        self.height = height
        self.bitDepth = bitDepth
        self.samples = floats
    }

    /// Plane 0 of a bi-planar Y'CbCr buffer as decoded: `420v`/`420f` (8-bit) or `x420`/`xf20` (10-bit,
    /// most-significant-bit aligned in 16-bit words).
    public init(pixelBuffer: CVPixelBuffer) throws {
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let tenBit: Bool
        switch format {
        case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange, kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
            tenBit = false
        case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange, kCVPixelFormatType_420YpCbCr10BiPlanarFullRange:
            tenBit = true
        default:
            throw LumaPlaneError.unsupportedPixelFormat(format)
        }
        guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else { throw LumaPlaneError.lockFailed }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { throw LumaPlaneError.lockFailed }
        var floats = [Float](repeating: 0, count: width * height)
        floats.withUnsafeMutableBufferPointer { out in
            for y in 0..<height {
                let row = base.advanced(by: y * stride)
                let target = out.baseAddress!.advanced(by: y * width)
                if tenBit {
                    // 10-bit samples sit in the top bits of 16-bit words: value = word >> 6, exactly floor(word / 64).
                    vDSP_vfltu16(row.assumingMemoryBound(to: UInt16.self), 1, target, 1, vDSP_Length(width))
                    var scale: Float = 1.0 / 64.0
                    vDSP_vsmul(target, 1, &scale, target, 1, vDSP_Length(width))
                    var count = Int32(width)
                    vvfloorf(target, target, &count)
                } else {
                    vDSP_vfltu8(row.assumingMemoryBound(to: UInt8.self), 1, target, 1, vDSP_Length(width))
                }
            }
        }
        self.init(width: width, height: height, bitDepth: tenBit ? 10 : 8, floats: floats)
    }

    /// A display-referred grey rendering of an image (8-bit, full range). Good for reading the frame code;
    /// not for signatures, which are defined on decoded luma code values.
    public init(image: CGImage) throws {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width, space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw LumaPlaneError.drawFailed }
        var floats = [Float](repeating: 0, count: width * height)
        vDSP_vfltu8(bytes, 1, &floats, 1, vDSP_Length(width * height))
        self.init(width: width, height: height, bitDepth: 8, floats: floats)
    }

    /// `floor(sum / count)` of the samples in `[x0, x1) x [y0, y1)`.
    public func mean(x0: Int, x1: Int, y0: Int, y1: Int) -> Int {
        var total = 0
        samples.withUnsafeBufferPointer { buffer in
            for y in y0..<y1 {
                var rowSum: Float = 0   // at most 1023 x row length: exact in Float
                vDSP_sve(buffer.baseAddress!.advanced(by: y * width + x0), 1, &rowSum, vDSP_Length(x1 - x0))
                total += Int(rowSum)
            }
        }
        return total / ((x1 - x0) * (y1 - y0))
    }
}
