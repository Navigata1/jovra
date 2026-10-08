import CryptoKit
import Foundation

/// `jovra.cellLuma.v1`, the decoder-independent frame signature defined in
/// `scripts/media/jovra_media/signature.py`: per cell of the coded picture, the mean luma of the cell's
/// central half (`floor(sum / count)`), reduced to 8 bits and quantized to `mean8 / 64`. The renderer keeps
/// every source cell at least 12 code values from a boundary, so any conformant decode yields the same levels.
public enum FrameSignature {
    public static let method = "jovra.cellLuma.v1"

    public static func cellMeans(of plane: LumaPlane, columns: Int, rows: Int) -> [Int] {
        precondition(plane.width % columns == 0 && plane.height % rows == 0, "grid must divide the picture")
        let cw = plane.width / columns, ch = plane.height / rows
        var means: [Int] = []
        means.reserveCapacity(columns * rows)
        for row in 0..<rows {
            for column in 0..<columns {
                means.append(plane.mean(x0: column * cw + cw / 4, x1: column * cw + (3 * cw) / 4,
                                        y0: row * ch + ch / 4, y1: row * ch + (3 * ch) / 4))
            }
        }
        return means
    }

    public static func levels(of plane: LumaPlane, columns: Int, rows: Int) -> [UInt8] {
        levels(means: cellMeans(of: plane, columns: columns, rows: rows), bitDepth: plane.bitDepth)
    }

    public static func levels(means: [Int], bitDepth: Int) -> [UInt8] {
        let shift = bitDepth - 8
        return means.map { UInt8(Swift.min(($0 >> shift) / 64, 3)) }
    }
}

/// SHA-256 over the signature levels of every frame of a clip, in presentation order.
public struct ClipSignatureHasher {
    private var sha = SHA256()
    public private(set) var frames = 0

    public init() {}

    public mutating func add(_ levels: [UInt8]) {
        sha.update(data: levels)
        frames += 1
    }

    public func hexDigest() -> String {
        sha.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// The burned-in frame code: the first `cells` signature cells in row-major order, most significant bit
/// first, a bright cell meaning 1.
public enum FrameCode {
    public static func read(from plane: LumaPlane, truth: GroundTruth) throws -> Int {
        read(means: FrameSignature.cellMeans(of: plane, columns: truth.signature.columns, rows: truth.signature.rows),
             bitDepth: plane.bitDepth, cells: truth.frameCode.cells)
    }

    public static func read(means: [Int], bitDepth: Int, cells: Int) -> Int {
        let shift = bitDepth - 8
        return means.prefix(cells).reduce(0) { code, mean in (code << 1) | ((mean >> shift) >= 128 ? 1 : 0) }
    }
}
