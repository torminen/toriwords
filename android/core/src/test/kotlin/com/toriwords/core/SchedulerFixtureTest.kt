package com.toriwords.core

import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertNull
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test
import org.junit.jupiter.params.ParameterizedTest
import org.junit.jupiter.params.provider.MethodSource
import kotlin.math.abs
import kotlin.math.max

class SchedulerFixtureTest {
    companion object {
        @JvmStatic fun dayBoundary() = Fixtures.cases("scheduler/day-boundary.json")
        @JvmStatic fun fsrsStep() = Fixtures.cases("scheduler/fsrs-step.json")
        @JvmStatic fun fsrsReplay() = Fixtures.cases("scheduler/fsrs-replay.json")

        fun parameters(file: JsonObject): FsrsParameters {
            val p = file.getValue("params")
            return FsrsParameters(p["w"].array.map { it.double }, p["desiredRetention"].double, p["maximumInterval"].int)
        }

        fun log(j: JsonElement, card: ToriId) =
            ReviewLogInput(id(j["id"]), card, j["reviewedAt"].long, j["utcOffsetMin"].int, j["rating"].intOrNull?.let { Rating.of(it) })

        /** S and D within 1e-9 relative; everything else exact. */
        fun assertState(s: CardState?, e: JsonElement, label: String) {
            if (s == null) {
                assertTrue(e.isNull, "$label: expected a state")
                return
            }
            fun close(a: Double, b: Double) = abs(a - b) <= 1e-9 * max(abs(a), abs(b))
            assertTrue(close(s.stability, e["stability"].double), "$label: S ${s.stability} vs ${e["stability"]}")
            assertTrue(close(s.difficulty, e["difficulty"].double), "$label: D ${s.difficulty} vs ${e["difficulty"]}")
            assertEquals(e["lastReviewDay"].int, s.lastReviewDay, "$label: lastReviewDay")
            assertEquals(e["dueDay"].int, s.dueDay, "$label: dueDay")
            assertEquals(e["interval"].intOrNull, s.interval, "$label: interval")
            assertEquals(e["reps"].int, s.reps, "$label: reps")
            assertEquals(e["lapses"].int, s.lapses, "$label: lapses")
            assertEquals(e["stage"].str, s.stage.wire, "$label: stage")
        }
    }

    @Test
    fun defaultParametersMatchFixtures() {
        assertEquals(FsrsParameters.DEFAULT, parameters(Fixtures.file("scheduler/fsrs-step.json")))
    }

    @ParameterizedTest(name = "{0}") @MethodSource
    fun dayBoundary(c: FixtureCase) {
        assertEquals(c["expected"].int, DayModel.dayNumber(c["tMs"].long, c["utcOffsetMin"].int))
    }

    @ParameterizedTest(name = "{0}") @MethodSource
    fun fsrsStep(c: FixtureCase) {
        val p = c["state"]
        val prev = if (p.isNull) {
            null
        } else {
            CardState(
                p["stability"].double, p["difficulty"].double, p["lastReviewDay"].int, p["lastReviewDay"].int,
                p["reps"].int, p["lapses"].int, Rating.REMEMBERED, null,
            )
        }
        val s = Fsrs.step(prev, id(c["cardId"]), c["reviewDay"].int, Rating.of(c["rating"].int)!!, parameters(c.file))
        assertState(s, c["expected"], c.toString())
    }

    @ParameterizedTest(name = "{0}") @MethodSource
    fun fsrsReplay(c: FixtureCase) {
        val card = id(c["cardId"])
        val p = parameters(c.file)
        val logs = c["logs"].array.map { log(it, card) }
        val rated = logs.sortedWith(ReviewLogInput.REPLAY_ORDER).filter { it.rating != null }
        val steps = c["expected"]["steps"].array
        assertEquals(steps.map { it["logId"].str }, rated.map { it.id.toString() })
        var state: CardState? = null
        for ((l, e) in rated.zip(steps)) {
            assertEquals(e["reviewDay"].int, l.reviewDay)
            state = Fsrs.step(state, card, l.reviewDay, l.rating!!, p)
            assertState(state, e, "${c} step ${l.id}")
        }
        val final = Fsrs.replay(card, logs, p)
        if (c["expected"]["final"].isNull) assertNull(final) else assertState(final, c["expected"]["final"], "$c final")
    }

    @Test
    fun entryStageRules() {
        val known = CardState(30.0, 5.0, 0, 30, 3, 0, Rating.REMEMBERED, 30)
        val learning = known.copy(stability = 5.0)
        assertEquals(CardStage.NEW, entryStage(emptyList()))
        assertEquals(CardStage.NEW, entryStage(listOf(null, null)))
        assertEquals(CardStage.KNOWN_WELL, entryStage(listOf(known, known)))
        assertEquals(CardStage.LEARNING, entryStage(listOf(known, null)))
        assertEquals(CardStage.LEARNING, entryStage(listOf(known, learning)))
    }
}
