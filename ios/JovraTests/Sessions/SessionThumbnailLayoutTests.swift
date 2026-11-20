import CoreGraphics
import SwiftUI
import Testing
import UIKit
@testable import Jovra

/// The library card's thumbnail keeps its 16:10 frame whatever the poster's shape. At accessibility text sizes
/// the thumbnail spans the card's width, so a filled poster that reported its own size would push the whole
/// Sessions screen wider than the iPhone (the AX5 audit failure on PR #557).
@MainActor
@Suite("Session thumbnail layout")
struct SessionThumbnailLayoutTests {
    /// A synthetic, flat-colour poster: no footage, only its shape matters here.
    private static func poster(width: Int, height: Int) throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.3, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    private static func fittingSize(of view: some View, width: CGFloat) -> CGSize {
        UIHostingController(rootView: view)
            .sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
    }

    @Test("a poster of any shape fills a 16:10 frame and never widens it", arguments: [
        (480, 270), // landscape 16:9
        (300, 480), // portrait, as an upright iPhone records
        (480, 480),
        (2, 900)
    ])
    func posterNeverWidensTheFrame(size: (Int, Int)) throws {
        let artwork = SessionThumbnailArtwork(poster: try Self.poster(width: size.0, height: size.1), isMatch: true)
        for width in [132.0, 338.0] {
            let fitted = Self.fittingSize(of: artwork.frame(maxWidth: .infinity), width: width)
            #expect(fitted.width <= width + 0.5, "poster \(size) at width \(width) laid out \(fitted)")
            #expect(abs(fitted.height - width * 10 / 16) <= 0.5, "poster \(size) at width \(width) laid out \(fitted)")
        }
    }

    @Test("without a poster the drawn court keeps the same 16:10 frame")
    func drawnCourtFrame() {
        let fitted = Self.fittingSize(of: SessionThumbnailArtwork(poster: nil, isMatch: false).frame(maxWidth: .infinity),
                                      width: 338)
        #expect(abs(fitted.width - 338) <= 0.5)
        #expect(abs(fitted.height - 338 * 10 / 16) <= 0.5)
    }
}
