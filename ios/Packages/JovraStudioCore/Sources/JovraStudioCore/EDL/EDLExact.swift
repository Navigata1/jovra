import Foundation

/// An exact signed integer of any size, for the EDL's rational arithmetic (S11).
///
/// The reference (`spec/reference/studio/edl.py`) computes session time with Python's unbounded `Fraction`. A real sync
/// rate such as 1000300102/1000000000 multiplied by a frame duration and compared across angles needs more than 64 bits,
/// so Int64 would either trap or round. Values that fit an `Int` stay on the fast path; anything else falls back to a
/// little-endian base-2^32 magnitude. Only what the validator needs is here: add, subtract, multiply, floor division
/// and comparison. Binary floating point never reaches a decision.
struct EDLInteger: Comparable, Hashable, Sendable, CustomStringConvertible {
    private enum Storage: Hashable, Sendable {
        case small(Int)
        case large(negative: Bool, magnitude: [UInt32])   // normalized: no trailing zero limbs, never fits an Int
    }

    private let storage: Storage

    init(_ value: Int) { storage = .small(value) }

    private init(negative: Bool, magnitude: [UInt32]) {
        var mag = magnitude
        while let last = mag.last, last == 0 { mag.removeLast() }
        if let small = Self.smallValue(negative: negative, magnitude: mag) {
            storage = .small(small)
        } else {
            storage = .large(negative: negative, magnitude: mag)
        }
    }

    static let zero = EDLInteger(0)
    static let one = EDLInteger(1)

    var isZero: Bool { if case .small(0) = storage { true } else { false } }
    var isNegative: Bool {
        switch storage {
        case .small(let v): v < 0
        case .large(let negative, _): negative
        }
    }

    /// The value when it fits an `Int`.
    var intValue: Int? { if case .small(let v) = storage { v } else { nil } }

    var description: String {
        switch storage {
        case .small(let v): return String(v)
        case .large(let negative, let magnitude):
            var digits: [Character] = []
            var mag = magnitude
            while !mag.isEmpty {
                var remainder: UInt64 = 0
                for i in stride(from: mag.count - 1, through: 0, by: -1) {
                    let current = (remainder << 32) | UInt64(mag[i])
                    mag[i] = UInt32(current / 10)
                    remainder = current % 10
                }
                digits.append(Character(String(remainder)))
                while let last = mag.last, last == 0 { mag.removeLast() }
            }
            return (negative ? "-" : "") + String(digits.reversed())
        }
    }

    // ----- parts ---------------------------------------------------------------------------------------------------

    private var parts: (negative: Bool, magnitude: [UInt32]) {
        switch storage {
        case .small(let v):
            var mag: [UInt32] = []
            var m = v.magnitude
            while m > 0 {
                mag.append(UInt32(truncatingIfNeeded: m))
                m >>= 32
            }
            return (v < 0, mag)
        case .large(let negative, let magnitude):
            return (negative, magnitude)
        }
    }

    private static func smallValue(negative: Bool, magnitude: [UInt32]) -> Int? {
        guard magnitude.count <= 2 else { return nil }
        var m: UInt64 = 0
        for (i, limb) in magnitude.enumerated() { m |= UInt64(limb) << (32 * UInt64(i)) }
        if negative {
            guard m <= UInt64(Int.max) + 1 else { return nil }
            return m == UInt64(Int.max) + 1 ? Int.min : -Int(m)
        }
        guard m <= UInt64(Int.max) else { return nil }
        return Int(m)
    }

    // ----- magnitude arithmetic ------------------------------------------------------------------------------------

    private static func compareMagnitude(_ a: [UInt32], _ b: [UInt32]) -> Int {
        if a.count != b.count { return a.count < b.count ? -1 : 1 }
        for i in stride(from: a.count - 1, through: 0, by: -1) where a[i] != b[i] {
            return a[i] < b[i] ? -1 : 1
        }
        return 0
    }

    private static func addMagnitude(_ a: [UInt32], _ b: [UInt32]) -> [UInt32] {
        var out: [UInt32] = []
        out.reserveCapacity(max(a.count, b.count) + 1)
        var carry: UInt64 = 0
        for i in 0..<max(a.count, b.count) {
            let sum = UInt64(i < a.count ? a[i] : 0) + UInt64(i < b.count ? b[i] : 0) + carry
            out.append(UInt32(truncatingIfNeeded: sum))
            carry = sum >> 32
        }
        if carry > 0 { out.append(UInt32(carry)) }
        return out
    }

    /// a - b for |a| >= |b|.
    private static func subtractMagnitude(_ a: [UInt32], _ b: [UInt32]) -> [UInt32] {
        var out: [UInt32] = []
        out.reserveCapacity(a.count)
        var borrow: Int64 = 0
        for i in 0..<a.count {
            var diff = Int64(a[i]) - Int64(i < b.count ? b[i] : 0) - borrow
            if diff < 0 {
                diff += 1 << 32
                borrow = 1
            } else {
                borrow = 0
            }
            out.append(UInt32(diff))
        }
        while let last = out.last, last == 0 { out.removeLast() }
        return out
    }

    private static func multiplyMagnitude(_ a: [UInt32], _ b: [UInt32]) -> [UInt32] {
        guard !a.isEmpty, !b.isEmpty else { return [] }
        var out = [UInt32](repeating: 0, count: a.count + b.count)
        for i in 0..<a.count {
            var carry: UInt64 = 0
            let ai = UInt64(a[i])
            for j in 0..<b.count {
                let current = ai * UInt64(b[j]) + UInt64(out[i + j]) + carry
                out[i + j] = UInt32(truncatingIfNeeded: current)
                carry = current >> 32
            }
            var k = i + b.count
            while carry > 0 {
                let current = UInt64(out[k]) + carry
                out[k] = UInt32(truncatingIfNeeded: current)
                carry = current >> 32
                k += 1
            }
        }
        return out
    }

    /// Truncating division of magnitudes (b non-empty), by binary long division.
    private static func divideMagnitude(_ a: [UInt32], _ b: [UInt32]) -> (quotient: [UInt32], remainder: [UInt32]) {
        if compareMagnitude(a, b) < 0 { return ([], a) }
        var quotient = [UInt32](repeating: 0, count: a.count)
        var remainder: [UInt32] = []
        for bit in stride(from: a.count * 32 - 1, through: 0, by: -1) {
            // remainder = remainder << 1 | bit of a
            var carry: UInt32 = (a[bit / 32] >> UInt32(bit % 32)) & 1
            for i in 0..<remainder.count {
                let next = remainder[i] >> 31
                remainder[i] = (remainder[i] << 1) | carry
                carry = next
            }
            if carry > 0 { remainder.append(carry) }
            if compareMagnitude(remainder, b) >= 0 {
                remainder = subtractMagnitude(remainder, b)
                quotient[bit / 32] |= 1 << UInt32(bit % 32)
            }
        }
        while let last = quotient.last, last == 0 { quotient.removeLast() }
        return (quotient, remainder)
    }

    // ----- signed arithmetic ---------------------------------------------------------------------------------------

    static func + (lhs: EDLInteger, rhs: EDLInteger) -> EDLInteger {
        if case .small(let a) = lhs.storage, case .small(let b) = rhs.storage {
            let (sum, overflow) = a.addingReportingOverflow(b)
            if !overflow { return EDLInteger(sum) }
        }
        let (an, am) = lhs.parts, (bn, bm) = rhs.parts
        if an == bn { return EDLInteger(negative: an, magnitude: addMagnitude(am, bm)) }
        let order = compareMagnitude(am, bm)
        if order == 0 { return .zero }
        return order > 0 ? EDLInteger(negative: an, magnitude: subtractMagnitude(am, bm))
            : EDLInteger(negative: bn, magnitude: subtractMagnitude(bm, am))
    }

    static prefix func - (value: EDLInteger) -> EDLInteger {
        if case .small(let v) = value.storage, v != .min { return EDLInteger(-v) }
        let (negative, magnitude) = value.parts
        return magnitude.isEmpty ? .zero : EDLInteger(negative: !negative, magnitude: magnitude)
    }

    static func - (lhs: EDLInteger, rhs: EDLInteger) -> EDLInteger { lhs + (-rhs) }

    static func * (lhs: EDLInteger, rhs: EDLInteger) -> EDLInteger {
        if case .small(let a) = lhs.storage, case .small(let b) = rhs.storage {
            let (product, overflow) = a.multipliedReportingOverflow(by: b)
            if !overflow { return EDLInteger(product) }
        }
        let (an, am) = lhs.parts, (bn, bm) = rhs.parts
        let magnitude = multiplyMagnitude(am, bm)
        return magnitude.isEmpty ? .zero : EDLInteger(negative: an != bn, magnitude: magnitude)
    }

    /// floor(lhs / rhs) for rhs > 0 (the only divisor the fractions use).
    static func floorDivide(_ lhs: EDLInteger, by rhs: EDLInteger) -> EDLInteger {
        precondition(!rhs.isNegative && !rhs.isZero, "EDLInteger.floorDivide needs a positive divisor")
        if case .small(let a) = lhs.storage, case .small(let b) = rhs.storage {
            let q = a / b, r = a % b
            return EDLInteger(r < 0 ? q - 1 : q)
        }
        let (an, am) = lhs.parts
        let (q, r) = divideMagnitude(am, rhs.parts.magnitude)
        let quotient = EDLInteger(negative: an, magnitude: q)
        return an && !r.isEmpty ? quotient - .one : quotient
    }

    static func < (lhs: EDLInteger, rhs: EDLInteger) -> Bool {
        if case .small(let a) = lhs.storage, case .small(let b) = rhs.storage { return a < b }
        let (an, am) = lhs.parts, (bn, bm) = rhs.parts
        if an != bn { return an }
        let order = compareMagnitude(am, bm)
        return an ? order > 0 : order < 0
    }
}

/// An exact rational number (the reference's `fractions.Fraction`) with a positive denominator. Fractions that fit an
/// `Int` are kept in lowest terms; larger ones are compared by cross-multiplication, so equality never depends on
/// reduction.
struct EDLFraction: Comparable, Sendable, CustomStringConvertible {
    let numerator: EDLInteger
    let denominator: EDLInteger

    init(_ numerator: EDLInteger, _ denominator: EDLInteger = .one) {
        precondition(!denominator.isZero, "EDLFraction with a zero denominator")
        var (n, d) = denominator.isNegative ? (-numerator, -denominator) : (numerator, denominator)
        if let a = n.intValue, let b = d.intValue, a != .min {
            let g = Self.gcd(a.magnitude, b.magnitude)
            if g > 1 {
                n = EDLInteger(a / Int(g))
                d = EDLInteger(b / Int(g))
            }
        }
        self.numerator = n
        self.denominator = d
    }

    init(_ numerator: Int, _ denominator: Int = 1) { self.init(EDLInteger(numerator), EDLInteger(denominator)) }

    static let zero = EDLFraction(0)
    static let half = EDLFraction(1, 2)

    var description: String { denominator == .one ? numerator.description : "\(numerator)/\(denominator)" }

    static func + (a: EDLFraction, b: EDLFraction) -> EDLFraction {
        if a.denominator == b.denominator { return EDLFraction(a.numerator + b.numerator, a.denominator) }
        return EDLFraction(a.numerator * b.denominator + b.numerator * a.denominator, a.denominator * b.denominator)
    }

    static func - (a: EDLFraction, b: EDLFraction) -> EDLFraction { a + EDLFraction(-b.numerator, b.denominator) }

    static func * (a: EDLFraction, b: EDLFraction) -> EDLFraction {
        EDLFraction(a.numerator * b.numerator, a.denominator * b.denominator)
    }

    static func / (a: EDLFraction, b: EDLFraction) -> EDLFraction {
        EDLFraction(a.numerator * b.denominator, a.denominator * b.numerator)
    }

    static func == (a: EDLFraction, b: EDLFraction) -> Bool {
        a.numerator * b.denominator == b.numerator * a.denominator
    }

    static func < (a: EDLFraction, b: EDLFraction) -> Bool {
        a.numerator * b.denominator < b.numerator * a.denominator
    }

    var floor: EDLInteger { EDLInteger.floorDivide(numerator, by: denominator) }
    var ceil: EDLInteger { -EDLInteger.floorDivide(-numerator, by: denominator) }
    /// floor(x + 1/2), the one rounding rule (`core.round_half_up`).
    var roundedHalfUp: EDLInteger { (self + .half).floor }
    var magnitude: EDLFraction { numerator.isNegative ? EDLFraction(-numerator, denominator) : self }

    private static func gcd(_ a: UInt, _ b: UInt) -> UInt {
        var (a, b) = (a, b)
        while b != 0 { (a, b) = (b, a % b) }
        return a
    }
}
