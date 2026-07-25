import Foundation

/// SplitMix64. Small, fast, well-distributed, and — the part that matters here —
/// identical on every device and every OS version.
///
/// The daily challenge promises everyone the same run from the same seed. That
/// promise cannot be built on `SystemRandomNumberGenerator`, whose sequence is
/// not reproducible, so the engine carries its own generator.
public struct SeededRandom: RandomNumberGenerator, Sendable {
    private var state: UInt64

    public init(seed: UInt64) {
        // Zero is a legal SplitMix64 state, but seeding with it makes the first
        // few outputs correlate across nearby seeds. Nudge it off zero.
        self.state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// Uniform double in `[0, 1)`.
    public mutating func nextUnitDouble() -> Double {
        // Top 53 bits: exactly the mantissa width of a Double, so every value is
        // representable and the distribution stays uniform.
        Double(next() >> 11) * (1.0 / 9_007_199_254_740_992.0)
    }

    /// Uniform double in `[lower, upper)`.
    public mutating func nextDouble(in range: Range<Double>) -> Double {
        range.lowerBound + nextUnitDouble() * (range.upperBound - range.lowerBound)
    }
}

public enum DailySeed {
    /// Stable seed for a calendar day in UTC, so the challenge rolls over at the
    /// same instant worldwide and two players in different time zones are
    /// genuinely competing on the same run.
    public static func seed(for date: Date = Date()) -> UInt64 {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let y = UInt64(parts.year ?? 2026)
        let m = UInt64(parts.month ?? 1)
        let d = UInt64(parts.day ?? 1)
        return y &* 10_000 &+ m &* 100 &+ d
    }

    /// `2026-07-25` style identifier used as the leaderboard key.
    public static func identifier(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
