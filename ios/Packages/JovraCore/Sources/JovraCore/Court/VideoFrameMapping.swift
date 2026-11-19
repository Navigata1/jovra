import Foundation

/// A point in a view's coordinate space (points, origin top-left). Foundation-only so JovraCore builds on Linux.
public struct PlanePoint: Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct PlaneSize: Hashable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

/// How the video is placed in its view (`AVLayerVideoGravity`): aspect fit with letterbox bars, or aspect fill.
public enum VideoGravity: String, Sendable, Codable, Hashable {
    case resizeAspect, resizeAspectFill
}

/// Converts taps in view points to video pixels before fitting (never fitted in view points), and video pixels
/// back to the view to draw the projected court. The video is centred in its view.
public struct VideoFrameMapping: Hashable, Sendable {
    public var viewSize: PlaneSize
    public var videoSize: PlaneSize
    public var gravity: VideoGravity

    public init(viewSize: PlaneSize, videoSize: PlaneSize, gravity: VideoGravity = .resizeAspect) {
        self.viewSize = viewSize
        self.videoSize = videoSize
        self.gravity = gravity
    }

    /// View points per video pixel.
    public var scale: Double {
        let sx = viewSize.width / videoSize.width, sy = viewSize.height / videoSize.height
        return gravity == .resizeAspect ? min(sx, sy) : max(sx, sy)
    }

    private var origin: PlanePoint {
        PlanePoint(x: (viewSize.width - videoSize.width * scale) / 2, y: (viewSize.height - videoSize.height * scale) / 2)
    }

    /// The video pixel under a view point; nil on a letterbox bar (outside the video).
    public func videoPixel(fromView point: PlanePoint) -> VideoPixel? {
        let x = (point.x - origin.x) / scale, y = (point.y - origin.y) / scale
        guard x >= 0, y >= 0, x <= videoSize.width, y <= videoSize.height else { return nil }
        return VideoPixel(x: x, y: y)
    }

    public func viewPoint(fromVideo pixel: VideoPixel) -> PlanePoint {
        PlanePoint(x: origin.x + pixel.x * scale, y: origin.y + pixel.y * scale)
    }
}
