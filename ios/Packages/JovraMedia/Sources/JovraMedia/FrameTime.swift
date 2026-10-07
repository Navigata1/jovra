import CoreMedia
import JovraCore

public extension CMTime {
    /// The exact presentation time at which `frame` starts, expressed in the rate's own timescale
    /// so no rounding is introduced (frame 30 at 30000/1001 fps is 30030/30000 s).
    init(frame: Int, at rate: FrameRate) {
        self.init(value: Int64(frame) * Int64(rate.perSeconds), timescale: CMTimeScale(rate.frames))
    }

    /// The frame on screen at this time, using integer arithmetic where it cannot overflow.
    /// Invalid, indefinite and negative times map to frame 0.
    func frameIndex(at rate: FrameRate) -> Int {
        guard isNumeric, value > 0, timescale > 0 else { return 0 }
        let (numerator, overflowA) = value.multipliedReportingOverflow(by: Int64(rate.frames))
        let (denominator, overflowB) = Int64(timescale).multipliedReportingOverflow(by: Int64(rate.perSeconds))
        if !overflowA && !overflowB {
            return Int(numerator / denominator)
        }
        return rate.frame(atSeconds: seconds)
    }
}
