import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Review days with the 04:00 local boundary. All maths in 64-bit integers, floor toward −∞.
public enum DayModel {
    public static func dayNumber(unixMs: Int64, utcOffsetMin: Int) -> Int {
        Int(floorDiv(floorDiv(unixMs, 1000) + Int64(utcOffsetMin) * 60 - 4 * 3600, 86400))
    }

    static func floorDiv(_ a: Int64, _ b: Int64) -> Int64 {
        let q = a / b
        return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
    }
}

public enum Rating: Int, Comparable, Codable, Sendable {
    case forgot = 1, hard = 2, remembered = 3, easy = 4
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
}

/// Card stage; the raw value is the stored name.
public enum CardStage: String, Codable, Sendable {
    case new, learning, knownWell = "known_well"
}

/// FSRS-6 parameter set; synced via Settings.
public struct FSRSParameters: Hashable, Codable, Sendable {
    public var w: [Double]
    public var desiredRetention: Double
    public var maximumInterval: Int

    public init(w: [Double], desiredRetention: Double, maximumInterval: Int = 36500) {
        precondition(w.count == 21, "FSRS-6 needs 21 weights")
        self.w = w
        self.desiredRetention = desiredRetention
        self.maximumInterval = maximumInterval
    }

    public static let `default` = FSRSParameters(
        w: [0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722,
            0.1666, 0.796, 1.4835, 0.0614, 0.2629, 1.6483, 0.6014, 1.8729, 0.5425,
            0.0912, 0.0658, 0.1542],
        desiredRetention: 0.90)

    var decay: Double { -w[20] }
    var factor: Double { pow(0.9, 1 / decay) - 1 }
}

/// Cached scheduling state of a started Card (a New Card has no state: `nil`).
public struct CardState: Hashable, Codable, Sendable {
    public var stability: Double
    public var difficulty: Double
    public var lastReviewDay: Int
    public var dueDay: Int
    public var reps: Int
    public var lapses: Int
    public var lastRating: Rating
    /// Rounded interval before fuzz from the last step; nil when `dueDay` = review day.
    public var interval: Int?

    public init(stability: Double, difficulty: Double, lastReviewDay: Int, dueDay: Int, reps: Int, lapses: Int,
                lastRating: Rating, interval: Int?) {
        self.stability = stability
        self.difficulty = difficulty
        self.lastReviewDay = lastReviewDay
        self.dueDay = dueDay
        self.reps = reps
        self.lapses = lapses
        self.lastRating = lastRating
        self.interval = interval
    }

    public var stage: CardStage { stability >= 21 && lastRating != .forgot ? .knownWell : .learning }

    public func isDue(on day: Int) -> Bool { dueDay <= day }
}

/// A rated or unrated (imported) review log as the scheduler sees it.
public struct ReviewLogInput: Hashable, Sendable {
    public var id: ToriID
    public var cardID: ToriID
    public var reviewedAt: Int64
    public var utcOffsetMin: Int
    public var rating: Rating?

    public init(id: ToriID, cardID: ToriID, reviewedAt: Int64, utcOffsetMin: Int, rating: Rating?) {
        self.id = id
        self.cardID = cardID
        self.reviewedAt = reviewedAt
        self.utcOffsetMin = utcOffsetMin
        self.rating = rating
    }

    public var reviewDay: Int { DayModel.dayNumber(unixMs: reviewedAt, utcOffsetMin: utcOffsetMin) }

    /// Replay order: `(reviewedAt, id as unsigned bytes)`.
    public static func replayOrder(_ a: Self, _ b: Self) -> Bool { (a.reviewedAt, a.id) < (b.reviewedAt, b.id) }
}

/// FSRS-6. Pure and deterministic: binary64, seeded fuzz, no clock reads.
public enum FSRS {
    public static func retrievability(elapsedDays t: Int, stability s: Double, _ p: FSRSParameters = .default) -> Double {
        pow(1 + p.factor * Double(t) / s, p.decay)
    }

    public static func interval(stability s: Double, _ p: FSRSParameters = .default) -> Int {
        let i = s / p.factor * (pow(p.desiredRetention, 1 / p.decay) - 1)
        return min(max(roundHalfUp(i), 1), p.maximumInterval)
    }

    static func roundHalfUp(_ x: Double) -> Int { Int((x + 0.5).rounded(.down)) }

    /// `u ∈ [0, 1)` from SHA-256(card ID bytes ‖ reps as UInt32 big-endian).
    static func fuzzSeed(cardID: ToriID, reps: Int) -> Double {
        let r = UInt32(reps)
        let data = cardID.bytes + [UInt8(r >> 24), UInt8(r >> 16 & 0xFF), UInt8(r >> 8 & 0xFF), UInt8(r & 0xFF)]
        let first8 = SHA256.hash(data: data).prefix(8).reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        return Double(first8 >> 11) / 9_007_199_254_740_992  // 2^53
    }

    static func fuzz(_ ivl: Int, cardID: ToriID, reps: Int, maximum: Int) -> Int {
        if ivl < 3 { return ivl }
        var delta = 1.0
        for (start, end, f) in [(2.5, 7.0, 0.15), (7.0, 20.0, 0.10), (20.0, Double.infinity, 0.05)] {
            delta += f * max(0, min(Double(ivl), end) - start)
        }
        let lo = max(2, roundHalfUp(Double(ivl) - delta))
        let hi = min(roundHalfUp(Double(ivl) + delta), maximum)
        return lo + Int((fuzzSeed(cardID: cardID, reps: reps) * Double(hi - lo + 1)).rounded(.down))
    }

    /// One review of `cardID` on `day` with `rating`, from `state` (nil = New).
    public static func step(_ state: CardState?, cardID: ToriID, day: Int, rating: Rating,
                            _ p: FSRSParameters = .default) -> CardState {
        let w = p.w, g = Double(rating.rawValue)
        func d0(_ g: Double) -> Double { w[4] - exp(w[5] * (g - 1)) + 1 }
        func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double { min(max(x, lo), hi) }
        var s: Double, d: Double, reps: Int, lapses: Int
        if let state {
            let s0 = state.stability, dPrev = state.difficulty
            let t = max(0, day - state.lastReviewDay)
            let dPrime = dPrev + (-w[6] * (g - 3)) * (10 - dPrev) / 9
            d = clamp(w[7] * d0(4) + (1 - w[7]) * dPrime, 1, 10)
            if t == 0 {
                var inc = exp(w[17] * (g - 3 + w[18])) * pow(s0, -w[19])
                // Same-day stability floor for G ≥ 2 (Hard too), as in py-fsrs 6.3.3. The fixtures follow py-fsrs.
                if rating >= .hard { inc = max(inc, 1) }
                s = s0 * inc
            } else {
                let r = retrievability(elapsedDays: t, stability: s0, p)
                if rating >= .hard {
                    let hard = rating == .hard ? w[15] : 1, easy = rating == .easy ? w[16] : 1
                    s = s0 * (exp(w[8]) * (11 - dPrev) * pow(s0, -w[9]) * (exp(w[10] * (1 - r)) - 1) * hard * easy + 1)
                } else {
                    let sf = w[11] * pow(dPrev, -w[12]) * (pow(s0 + 1, w[13]) - 1) * exp(w[14] * (1 - r))
                    s = min(sf, s0 / exp(w[17] * w[18]))
                }
            }
            reps = state.reps + 1
            lapses = state.lapses + (rating == .forgot ? 1 : 0)
        } else {
            s = w[rating.rawValue - 1]
            d = clamp(d0(g), 1, 10)
            (reps, lapses) = (1, 0)
        }
        s = clamp(s, 0.001, 36500)
        var due = day, ivl: Int?
        if !(rating == .forgot || (state == nil && rating == .hard)) {
            ivl = interval(stability: s, p)
            due = day + fuzz(ivl!, cardID: cardID, reps: reps, maximum: p.maximumInterval)
        }
        return CardState(stability: s, difficulty: d, lastReviewDay: day, dueDay: due, reps: reps, lapses: lapses,
                         lastRating: rating, interval: ivl)
    }

    /// Card state = replay of its logs: sorted by (reviewedAt, id), unrated logs skipped. Nil = New.
    public static func replay(cardID: ToriID, logs: [ReviewLogInput], _ p: FSRSParameters = .default) -> CardState? {
        logs.sorted(by: ReviewLogInput.replayOrder).reduce(nil) { state, log in
            guard let rating = log.rating else { return state }
            return step(state, cardID: cardID, day: log.reviewDay, rating: rating, p)
        }
    }
}

/// Entry-level stage: New if no live Card has a rated log (or there are no Cards); Known well if every
/// live Card is `known_well`; otherwise Learning. Pass the state of each live Card (nil = New Card).
public func entryStage(cardStates: [CardState?]) -> CardStage {
    let started = cardStates.compactMap { $0 }
    if started.isEmpty { return .new }
    return started.count == cardStates.count && started.allSatisfy { $0.stage == .knownWell } ? .knownWell : .learning
}
