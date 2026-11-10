import CoreGraphics
import Testing
@testable import Jovra

/// T13, story 63: the 2x loupe shows the corner the finger covers, so it must stay inside the frame it magnifies
/// and never sit on the finger. Expected positions are worked by hand from the 112 pt diameter and 96 pt lift.
@Suite("Loupe placement")
struct LoupePlacementTests {
    @Test("with room above, the loupe sits 96 pt above the finger")
    func above() {
        let centre = LoupePlacement.centre(touch: CGPoint(x: 200, y: 300), in: CGSize(width: 400, height: 600), diameter: 112)
        #expect(centre == CGPoint(x: 200, y: 204))
    }

    @Test("near a side edge it slides in so the whole circle shows")
    func slidesInFromTheSide() {
        let centre = LoupePlacement.centre(touch: CGPoint(x: 10, y: 300), in: CGSize(width: 400, height: 600), diameter: 112)
        #expect(centre == CGPoint(x: 56, y: 204))
    }

    @Test("with no room above it moves beside the finger, towards the middle of the frame, never below it")
    func besideWhenThereIsNoRoomAbove() {
        let frame = CGSize(width: 400, height: 225)
        // A far corner near the top of a 16:9 frame: 40 - 96 leaves no room for a 56 pt radius.
        #expect(LoupePlacement.centre(touch: CGPoint(x: 300, y: 40), in: frame, diameter: 112) == CGPoint(x: 204, y: 56))
        #expect(LoupePlacement.centre(touch: CGPoint(x: 60, y: 40), in: frame, diameter: 112) == CGPoint(x: 156, y: 56))
    }

    @Test("everywhere in a phone-width 16:9 frame the loupe is whole and clear of the finger")
    func alwaysInsideAndClearOfTheFinger() {
        let frame = CGSize(width: 330, height: 186), radius: CGFloat = 56
        for x in stride(from: CGFloat(0), through: frame.width, by: 10) {
            for y in stride(from: CGFloat(0), through: frame.height, by: 6) {
                let touch = CGPoint(x: x, y: y)
                let centre = LoupePlacement.centre(touch: touch, in: frame, diameter: radius * 2)
                #expect(centre.x >= radius && centre.x <= frame.width - radius, "x at \(touch)")
                #expect(centre.y >= radius && centre.y <= frame.height - radius, "y at \(touch)")
                let distance = ((centre.x - touch.x) * (centre.x - touch.x) + (centre.y - touch.y) * (centre.y - touch.y)).squareRoot()
                #expect(distance >= radius, "the loupe covers the finger at \(touch)")
            }
        }
    }

    @Test("a frame smaller than the loupe centres it instead of trapping")
    func tinyFrame() {
        let centre = LoupePlacement.centre(touch: CGPoint(x: 20, y: 20), in: CGSize(width: 80, height: 60), diameter: 112)
        #expect(centre == CGPoint(x: 40, y: 30))
    }
}
