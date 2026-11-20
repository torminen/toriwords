package com.toriwords.core

import java.security.MessageDigest
import kotlin.math.floor

/** Review days with the 04:00 local boundary. All maths in 64-bit integers, floor toward −∞. */
object DayModel {
    fun dayNumber(unixMs: Long, utcOffsetMin: Int): Int =
        Math.floorDiv(Math.floorDiv(unixMs, 1000L) + utcOffsetMin * 60L - 4 * 3600L, 86400L).toInt()
}

enum class Rating(val value: Int) {
    FORGOT(1), HARD(2), REMEMBERED(3), EASY(4);

    companion object {
        fun of(value: Int): Rating? = entries.firstOrNull { it.value == value }
    }
}

/** Card stage; `wire` is the stored name. */
enum class CardStage(val wire: String) { NEW("new"), LEARNING("learning"), KNOWN_WELL("known_well") }

/** FSRS-6 parameter set; synced via Settings. */
data class FsrsParameters(val w: List<Double>, val desiredRetention: Double, val maximumInterval: Int = 36500) {
    init {
        require(w.size == 21) { "FSRS-6 needs 21 weights" }
    }

    internal val decay: Double get() = -w[20]
    internal val factor: Double get() = StrictMath.pow(0.9, 1 / decay) - 1

    companion object {
        val DEFAULT = FsrsParameters(
            w = listOf(
                0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722,
                0.1666, 0.796, 1.4835, 0.0614, 0.2629, 1.6483, 0.6014, 1.8729, 0.5425,
                0.0912, 0.0658, 0.1542,
            ),
            desiredRetention = 0.90,
        )
    }
}

/** Cached scheduling state of a started Card (a New Card has no state: null). */
data class CardState(
    val stability: Double,
    val difficulty: Double,
    val lastReviewDay: Int,
    val dueDay: Int,
    val reps: Int,
    val lapses: Int,
    val lastRating: Rating,
    /** Rounded interval before fuzz from the last step; null when `dueDay` = review day. */
    val interval: Int?,
) {
    val stage: CardStage get() = if (stability >= 21 && lastRating != Rating.FORGOT) CardStage.KNOWN_WELL else CardStage.LEARNING

    fun isDue(day: Int): Boolean = dueDay <= day
}

/** A rated or unrated (imported) review log as the scheduler sees it. */
data class ReviewLogInput(
    val id: ToriId,
    val cardId: ToriId,
    val reviewedAt: Long,
    val utcOffsetMin: Int,
    val rating: Rating?,
) {
    val reviewDay: Int get() = DayModel.dayNumber(reviewedAt, utcOffsetMin)

    companion object {
        /** Replay order: `(reviewedAt, id as unsigned bytes)`. */
        val REPLAY_ORDER: Comparator<ReviewLogInput> = compareBy<ReviewLogInput> { it.reviewedAt }.thenBy { it.id }
    }
}

/**
 * FSRS-6. Pure and deterministic: binary64, seeded fuzz, no clock reads. `StrictMath` so host JVM and ART give
 * bit-identical results (doc 38 §7.2, CH-21).
 */
object Fsrs {
    fun retrievability(elapsedDays: Int, stability: Double, p: FsrsParameters = FsrsParameters.DEFAULT): Double =
        StrictMath.pow(1 + p.factor * elapsedDays / stability, p.decay)

    fun interval(stability: Double, p: FsrsParameters = FsrsParameters.DEFAULT): Int {
        val i = stability / p.factor * (StrictMath.pow(p.desiredRetention, 1 / p.decay) - 1)
        return roundHalfUp(i).coerceIn(1, p.maximumInterval)
    }

    private fun roundHalfUp(x: Double): Int = floor(x + 0.5).toInt()

    /** `u ∈ [0, 1)` from SHA-256(card ID bytes ‖ reps as UInt32 big-endian). */
    internal fun fuzzSeed(cardId: ToriId, reps: Int): Double {
        val sha = MessageDigest.getInstance("SHA-256")
        sha.update(cardId.bytes)
        val digest = sha.digest(byteArrayOf((reps ushr 24).toByte(), (reps ushr 16).toByte(), (reps ushr 8).toByte(), reps.toByte()))
        var first8 = 0UL
        for (i in 0 until 8) first8 = (first8 shl 8) or digest[i].toUByte().toULong()
        return (first8 shr 11).toDouble() / 9_007_199_254_740_992.0 // 2^53
    }

    private fun fuzz(ivl: Int, cardId: ToriId, reps: Int, maximum: Int): Int {
        if (ivl < 3) return ivl
        var delta = 1.0
        for ((start, end, f) in listOf(Triple(2.5, 7.0, 0.15), Triple(7.0, 20.0, 0.10), Triple(20.0, Double.POSITIVE_INFINITY, 0.05))) {
            delta += f * maxOf(0.0, minOf(ivl.toDouble(), end) - start)
        }
        val lo = maxOf(2, roundHalfUp(ivl - delta))
        val hi = minOf(roundHalfUp(ivl + delta), maximum)
        return lo + floor(fuzzSeed(cardId, reps) * (hi - lo + 1)).toInt()
    }

    /** One review of `cardId` on `day` with `rating`, from `state` (null = New). */
    fun step(state: CardState?, cardId: ToriId, day: Int, rating: Rating, p: FsrsParameters = FsrsParameters.DEFAULT): CardState {
        val w = p.w
        val g = rating.value.toDouble()
        fun d0(g: Double) = w[4] - StrictMath.exp(w[5] * (g - 1)) + 1
        var s: Double
        val d: Double
        val reps: Int
        val lapses: Int
        if (state != null) {
            val s0 = state.stability
            val dPrev = state.difficulty
            val t = maxOf(0, day - state.lastReviewDay)
            val dPrime = dPrev + (-w[6] * (g - 3)) * (10 - dPrev) / 9
            d = (w[7] * d0(4.0) + (1 - w[7]) * dPrime).coerceIn(1.0, 10.0)
            if (t == 0) {
                var inc = StrictMath.exp(w[17] * (g - 3 + w[18])) * StrictMath.pow(s0, -w[19])
                // Same-day stability floor for G ≥ 2 (Hard too), as in py-fsrs 6.3.3. The fixtures follow py-fsrs.
                if (rating >= Rating.HARD) inc = maxOf(inc, 1.0)
                s = s0 * inc
            } else {
                val r = retrievability(t, s0, p)
                s = if (rating >= Rating.HARD) {
                    val hard = if (rating == Rating.HARD) w[15] else 1.0
                    val easy = if (rating == Rating.EASY) w[16] else 1.0
                    s0 * (StrictMath.exp(w[8]) * (11 - dPrev) * StrictMath.pow(s0, -w[9]) *
                        (StrictMath.exp(w[10] * (1 - r)) - 1) * hard * easy + 1)
                } else {
                    val sf = w[11] * StrictMath.pow(dPrev, -w[12]) * (StrictMath.pow(s0 + 1, w[13]) - 1) *
                        StrictMath.exp(w[14] * (1 - r))
                    minOf(sf, s0 / StrictMath.exp(w[17] * w[18]))
                }
            }
            reps = state.reps + 1
            lapses = state.lapses + if (rating == Rating.FORGOT) 1 else 0
        } else {
            s = w[rating.value - 1]
            d = d0(g).coerceIn(1.0, 10.0)
            reps = 1
            lapses = 0
        }
        s = s.coerceIn(0.001, 36500.0)
        var due = day
        var ivl: Int? = null
        if (!(rating == Rating.FORGOT || (state == null && rating == Rating.HARD))) {
            val i = interval(s, p)
            ivl = i
            due = day + fuzz(i, cardId, reps, p.maximumInterval)
        }
        return CardState(s, d, day, due, reps, lapses, rating, ivl)
    }

    /** Card state = replay of its logs: sorted by (reviewedAt, id), unrated logs skipped. Null = New. */
    fun replay(cardId: ToriId, logs: List<ReviewLogInput>, p: FsrsParameters = FsrsParameters.DEFAULT): CardState? =
        logs.sortedWith(ReviewLogInput.REPLAY_ORDER).fold(null as CardState?) { state, log ->
            val rating = log.rating ?: return@fold state
            step(state, cardId, log.reviewDay, rating, p)
        }
}

/**
 * Entry-level stage: New if no live Card has a rated log (or there are no Cards); Known well if every live Card is
 * `known_well`; otherwise Learning. Pass the state of each live Card (null = New Card).
 */
fun entryStage(cardStates: List<CardState?>): CardStage {
    val started = cardStates.filterNotNull()
    if (started.isEmpty()) return CardStage.NEW
    return if (started.size == cardStates.size && started.all { it.stage == CardStage.KNOWN_WELL }) CardStage.KNOWN_WELL else CardStage.LEARNING
}
