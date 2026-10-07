// Renders the JOVRA app icon (and an optional brand proof sheet) from the same vector geometry
// the app uses: ios/Jovra/DesignSystem/Brand/BrandGeometry.swift. Run via scripts/ios/render-app-icon.sh.
//
//   main <icon.png> [proof.png]
//
// The icon is 1024×1024, opaque (no alpha channel): forest background, ivory mark, chartreuse ball.
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let forest = CGColor(srgbRed: 0x09 / 255, green: 0x2A / 255, blue: 0x25 / 255, alpha: 1)
let ivory = CGColor(srgbRed: 0xF4 / 255, green: 0xF1 / 255, blue: 0xE8 / 255, alpha: 1)
let chartreuse = CGColor(srgbRed: 0xD7 / 255, green: 0xF5 / 255, blue: 0x6A / 255, alpha: 1)

func makeContext(width: Int, height: Int) -> CGContext {
    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { fatalError("Could not create bitmap context") }
    // Flip to a top-left origin so the geometry (authored y-down) draws upright.
    context.translateBy(x: 0, y: CGFloat(height))
    context.scaleBy(x: 1, y: -1)
    return context
}

func drawMark(in context: CGContext, rect: CGRect, letters: CGColor, ball: CGColor) {
    var fit = BrandGeometry.fitting(BrandGeometry.markBounds, into: rect)
    context.addPath(BrandGeometry.markLetters.copy(using: &fit)!)
    context.setFillColor(letters)
    context.fillPath()
    context.addPath(BrandGeometry.markBall.copy(using: &fit)!)
    context.setFillColor(ball)
    context.fillPath()
}

func write(_ context: CGContext, to path: String) {
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { fatalError("Could not write \(path)") }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Could not finalize \(path)") }
    print("wrote \(path)")
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: main <icon.png> [proof.png]\n".utf8))
    exit(64)
}

// App icon: the mark occupies ~62% of the canvas width, optically centred (nudged down for the ball).
let iconSize = 1024
let icon = makeContext(width: iconSize, height: iconSize)
icon.setFillColor(forest)
icon.fill(CGRect(x: 0, y: 0, width: iconSize, height: iconSize))
drawMark(in: icon, rect: CGRect(x: 196, y: 226, width: 632, height: 572), letters: ivory, ball: chartreuse)
write(icon, to: arguments[1])

// Optional proof sheet: lockup plus the mark at small sizes, for visual review.
if arguments.count >= 3 {
    let proof = makeContext(width: 1600, height: 900)
    proof.setFillColor(forest)
    proof.fill(CGRect(x: 0, y: 0, width: 1600, height: 450))
    proof.setFillColor(ivory)
    proof.fill(CGRect(x: 0, y: 450, width: 1600, height: 450))
    drawMark(in: proof, rect: CGRect(x: 80, y: 80, width: 420, height: 300), letters: ivory, ball: chartreuse)
    var fit = BrandGeometry.fitting(BrandGeometry.wordmarkBounds, into: CGRect(x: 560, y: 150, width: 900, height: 140))
    proof.addPath(BrandGeometry.wordmark.copy(using: &fit)!)
    proof.setFillColor(ivory)
    proof.fillPath()
    var x: CGFloat = 80
    for size: CGFloat in [180, 120, 60, 40, 29, 20] {
        drawMark(in: proof, rect: CGRect(x: x, y: 520, width: size, height: size), letters: forest, ball: chartreuse)
        x += size + 40
    }
    var fit2 = BrandGeometry.fitting(BrandGeometry.wordmarkBounds, into: CGRect(x: 80, y: 760, width: 500, height: 60))
    proof.addPath(BrandGeometry.wordmark.copy(using: &fit2)!)
    proof.setFillColor(forest)
    proof.fillPath()
    write(proof, to: arguments[2])
}
