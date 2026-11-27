"""Generates spec/fixtures/scheduler/*.json from torifix.scheduler (scheduler, day model, daily queue, widget snapshot).

Deterministic: fixed inputs, no clock reads, stable JSON formatting. Run: `uv run python generate.py`.
"""

import json
from pathlib import Path

from torifix import ids
from torifix.scheduler import (DESIRED_RETENTION, MAX_INTERVAL, W, CardState, Entry, Card, Log, build_queue,
                               day_number, replay, snapshot, step)

OUT = Path(__file__).resolve().parents[2] / "spec" / "fixtures" / "scheduler"
OFFSET = 180  # UTC+3
T = 20774  # "today" in the queue fixtures (2026-11-17)
PARAMS = {"w": W, "desiredRetention": DESIRED_RETENTION, "maximumInterval": MAX_INTERVAL}


def at(day: int, hour: int = 10, minute: int = 0, offset: int = OFFSET) -> int:
    """Unix ms of local wall time hour:minute (hour ≥ 4) belonging to review day `day`."""
    return ((day * 86400 + hour * 3600 + minute * 60) - offset * 60) * 1000


def write(name: str, doc: dict) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / name).write_text(json.dumps(doc, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def state_json(s: CardState) -> dict:
    return {"stability": s.stability, "difficulty": s.difficulty, "lastReviewDay": s.last_review_day,
            "dueDay": s.due_day, "interval": s.interval, "reps": s.reps, "lapses": s.lapses, "stage": s.stage}


class Ids:
    """Deterministic UUIDv7 ids: time part = the record's own instant, random parts = a running counter."""

    def __init__(self):
        self.n = 0

    def v7(self, ms: int) -> str:
        self.n += 1
        return ids.v7(ms, self.n & 0xFFF, self.n)


# --- day boundary --------------------------------------------------------------------------------

def day_boundary() -> None:
    d = 20774
    cases = [
        ("db-001", at(d, 4, 0), 180, "04:00 local starts the day"),
        ("db-002", at(d, 4, 0) - 1, 180, "03:59:59.999 local belongs to the previous day"),
        ("db-003", at(d, 23, 59), 180, None),
        ("db-004", at(d, 4, 0) + 86_400_000 - 1, 180, "one ms before the next 04:00"),
        ("db-005", at(d, 10, 0, 0), 0, "UTC"),
        ("db-006", at(d, 10, 0, -720), -720, "UTC−12"),
        ("db-007", at(d, 10, 0, 840), 840, "UTC+14"),
        ("db-008", at(d, 4, 0, 330), 330, "UTC+5:30, exactly 04:00"),
        ("db-009", at(d, 4, 0, 345) - 1, 345, "UTC+5:45, just before 04:00"),
        ("db-010", 0, 0, "epoch at UTC: 1970-01-01 00:00 is before 04:00 → day −1"),
        ("db-011", -1, 0, "negative instant: floor toward −∞"),
        ("db-012", -86_400_000 * 365 - 1, 180, "far before epoch"),
        ("db-013", 1_000, -300, "floorDiv of a negative sum"),
        ("db-014", 4 * 3600 * 1000 - 1, 0, None),
        ("db-015", 4 * 3600 * 1000, 0, "1970-01-01 04:00 UTC = day 0"),
    ]
    out = []
    for cid, t, off, note in cases:
        c = {"id": cid, "tMs": t, "utcOffsetMin": off, "expected": day_number(t, off)}
        if note:
            c["note"] = note
        out.append(c)
    write("day-boundary.json", {"kind": "day-boundary",
        "source": "Day model: dayNumber(t_ms, offsetMin) = floorDiv(floorDiv(t_ms, 1000) + offsetMin*60 − 4*3600, 86400), 64-bit, floor toward −∞",
        "cases": out})


# --- FSRS step ------------------------------------------------------------------------------------

CARD_A = ids.v5("card:0192f3c1-7a4e-7cc3-9b1e-3f5a2d6c8e01:recognition")
CARD_B = ids.v5("card:0192f3c1-7a4e-7cc3-9b1e-3f5a2d6c8e01:recall")


def fsrs_step() -> None:
    cases = []

    def add(cid, prev, card, day, g, note=None):
        res = step(prev, card, day, g)
        c = {"id": cid, "cardId": card, "state": None if prev is None else {
                 "stability": prev.stability, "difficulty": prev.difficulty, "lastReviewDay": prev.last_review_day,
                 "reps": prev.reps, "lapses": prev.lapses},
             "reviewDay": day, "rating": g, "expected": state_json(res)}
        if note:
            c["note"] = note
        cases.append(c)

    n = 0
    for g in (1, 2, 3, 4):
        n += 1
        add(f"st-{n:03d}", None, CARD_A, T, g, "first review of a new card" + (" (G=2: re-show, imports only)" if g == 2 else ""))
    base = [
        (CardState(2.3065, 2.118103970459016, T - 10, T - 8, 1, 0, 3, 2), "young card"),
        (CardState(15.0, 5.0, T - 20, T - 2, 4, 1, 3, 15), "mid card"),
        (CardState(120.0, 8.5, T - 130, T - 10, 9, 2, 3, 120), "mature, hard card"),
    ]
    for prev, label in base:
        for elapsed in (0, 1, 10, 100):
            for g in (1, 2, 3, 4):
                n += 1
                add(f"st-{n:03d}", prev, CARD_A, prev.last_review_day + elapsed, g, f"{label}, t = {elapsed}")
    extremes = [
        (CardState(36000.0, 1.0, T - 3000, T, 30, 0, 3, 36500), T, 4, "S clamped to 36500, interval capped at 36500"),
        (CardState(0.001, 10.0, T - 1, T, 5, 4, 1, None), T, 1, "S floor 0.001, D at 10"),
        (CardState(0.5, 1.0, T - 1, T, 2, 0, 3, 1), T, 4, "D floor 1"),
        (CardState(3.0, 5.0, T - 5, T - 2, 2, 0, 3, 3), T - 10, 3, "review day before the last review day: t clamped to 0"),
        (CardState(20.9, 4.0, T - 25, T - 2, 5, 0, 3, 21), T, 3, "crosses S ≥ 21 → known_well"),
        (CardState(40.0, 4.0, T - 45, T - 2, 6, 0, 3, 40), T, 1, "lapse of a known_well card → learning"),
    ]
    for prev, day, g, note in extremes:
        n += 1
        add(f"st-{n:03d}", prev, CARD_B, day, g, note)
    write("fsrs-step.json", {"kind": "fsrs-step",
        "source": "FSRS-6 step, intervals, fuzz and stage. state = previous state or null for a new card. expected.interval = rounded interval before fuzz (null when dueDay = reviewDay). S and D within 1e-9 relative; everything else exact",
        "params": PARAMS, "cases": cases})


# --- replay ---------------------------------------------------------------------------------------

def fsrs_replay() -> None:
    g = Ids()
    cases = []

    def add(cid, card, logs, note):
        lg = [Log(l["id"], card, l["reviewedAt"], l["utcOffsetMin"], l["rating"]) for l in logs]
        steps, st = [], None
        for log in sorted(lg, key=Log.sort_key):
            if log.rating is not None:
                st = step(st, card, log.day, log.rating)
                steps.append({"logId": log.id, "reviewDay": log.day, **state_json(st)})
        final = replay(card, lg)
        cases.append({"id": cid, "cardId": card, "logs": logs, "note": note,
                      "expected": {"steps": steps, "final": None if final is None else state_json(final)}})

    def log(day, rating, hour=10, minute=0, offset=OFFSET, lid=None, ms=None):
        t = at(day, hour, minute, offset) if ms is None else ms
        return {"id": lid or g.v7(t), "reviewedAt": t, "utcOffsetMin": offset, "rating": rating}

    add("rp-001", CARD_A, [log(T - 40, 3), log(T - 38, 3), log(T - 30, 3), log(T - 10, 3), log(T, 3)],
        "steady Remembered history")
    add("rp-002", CARD_A, [log(T - 40, 3), log(T - 40, 1, 11), log(T - 40, 3, 12), log(T - 39, 1), log(T - 37, 3), log(T - 20, 3)],
        "Forgot and same-day re-shows")
    add("rp-003", CARD_A, [log(T - 30, None), log(T - 29, 3), log(T - 28, None), log(T - 20, 4), log(T - 5, 2)],
        "imported null ratings are skipped (not counted in reps)")
    a, b, c = log(T - 10, 3), log(T - 8, 1), log(T - 3, 3)
    add("rp-004", CARD_A, [c, a, b], "logs given out of order: sorted by (reviewedAt, id)")
    t0 = at(T - 5, 10)
    lo = "0192f3c1-0000-7000-8000-000000000001"
    hi = "0192f3c1-0000-7000-8000-0000000000ff"
    add("rp-005", CARD_A, [log(T - 9, 3), {"id": hi, "reviewedAt": t0, "utcOffsetMin": OFFSET, "rating": 3},
                           {"id": lo, "reviewedAt": t0, "utcOffsetMin": OFFSET, "rating": 1}],
        "equal reviewedAt: tie broken by id (unsigned bytes), so the Forgot comes first")
    # Time-zone travel: second log is later in time but its review day (in its own offset) is earlier.
    t1 = at(T - 5, 23, 30, 600)
    t2 = t1 + 3_600_000
    add("rp-006", CARD_A, [log(T - 9, 3), {"id": g.v7(t1), "reviewedAt": t1, "utcOffsetMin": 600, "rating": 3},
                           {"id": g.v7(t2), "reviewedAt": t2, "utcOffsetMin": -600, "rating": 3}],
        "time-zone change: a later log with an earlier review day (elapsed clamped to 0)")
    add("rp-007", CARD_A, [log(T - 3, None)], "only null ratings → still new (final null)")
    add("rp-008", CARD_B, [log(T - 1, 2), log(T - 1, 3, 15)], "imported first answer Hard (G=2) stays due that day, then Good")
    write("fsrs-replay.json", {"kind": "fsrs-replay",
        "source": "Card state replay: sort by (reviewedAt, id as unsigned bytes), skip rating null, review day = dayNumber(reviewedAt, utcOffsetMin), fold the FSRS-6 step from new. expected.steps = state after each rated log in replay order",
        "params": PARAMS, "cases": cases})


# --- queue and snapshot ---------------------------------------------------------------------------

class World:
    def __init__(self):
        self.g = Ids()
        self.entries: list[Entry] = []
        self.logs: list[Log] = []

    def entry(self, created_day: int, directions=("recognition", "recall"), status="active") -> Entry:
        created = at(created_day, 9)
        eid = self.g.v7(created)
        e = Entry(eid, created, status, [Card(ids.v5(f"card:{eid}:{d}"), d) for d in directions])
        self.entries.append(e)
        return e

    def review(self, card: Card, day: int, rating: int, hour: int = 10, minute: int = 0) -> None:
        t = at(day, hour, minute)
        self.logs.append(Log(self.g.v7(t), card.id, t, OFFSET, rating))

    def inputs(self, new_words_per_day: int, now: int) -> dict:
        return {
            "now": now, "utcOffsetMin": OFFSET, "settings": {"newWordsPerDay": new_words_per_day},
            "entries": [{"id": e.id, "createdAt": e.created_at, "status": e.status,
                         "cards": [{"id": c.id, "direction": c.direction} for c in e.cards]} for e in self.entries],
            "logs": [{"id": l.id, "cardId": l.card_id, "reviewedAt": l.reviewed_at, "utcOffsetMin": l.utc_offset_min,
                      "rating": l.rating} for l in self.logs],
        }


NOW = at(T, 18)


def queue_case(cid: str, w: World, note: str, limit: int = 10, now: int = NOW) -> dict:
    q = build_queue(w.entries, w.logs, day_number(now, OFFSET), limit)
    return {"id": cid, "note": note, "input": w.inputs(limit, now), "expected": {
        "reviews": q.reviews, "new": q.new, "reshow": q.reshow,
        "dueToday": {"toReview": len(q.reviews) + len(q.reshow), "new": len(q.new)},
        "waiting": q.waiting, "catchUp": q.catch_up, "normalLoad": q.normal_load, "homeState": q.home_state}}


QUEUE_SOURCE = ("Daily queue and catch-up, Home states; day = dayNumber(now, utcOffsetMin). Card state comes "
                "from replaying the input logs. Input entries are live; cards are live Cards. reshow is ordered by "
                "card id (unsigned bytes). dueToday.toReview = steps 1 + 3, dueToday.new = step 2")


def queue_basic() -> None:
    cases = []
    cases.append(queue_case("qb-001", World(), "no Entries → empty"))
    w = World(); w.entry(T - 3, ()); w.entry(T - 2, ())
    cases.append(queue_case("qb-002", w, "Entries without Cards (Needs translation) → noneReviewable"))
    w = World(); w.entry(T - 3, status="excluded"); 
    cases.append(queue_case("qb-003", w, "only excluded Entries, all translated → nothingDue"))
    w = World(); [w.entry(T - 3 + i) for i in range(3)]
    cases.append(queue_case("qb-004", w, "three New Entries: one Card each (sibling filter), oldest Entry first, recognition first"))
    w = World()
    e1, e2, e3 = w.entry(T - 60, ("recognition",)), w.entry(T - 60, ("recognition",)), w.entry(T - 60, ("recognition",))
    w.review(e1.cards[0], T - 50, 3); w.review(e1.cards[0], T - 45, 3)
    w.review(e2.cards[0], T - 30, 3)
    w.review(e3.cards[0], T - 20, 3); w.review(e3.cards[0], T - 18, 1); w.review(e3.cards[0], T - 18, 3, 12)
    cases.append(queue_case("qb-005", w, "waiting Cards ordered by retrievability ascending, then due day, then id"))
    w = World(); e = w.entry(T - 10, ("recognition",)); w.review(e.cards[0], T - 1, 3)
    cases.append(queue_case("qb-006", w, "started Card due in the future, nothing new → nothingDue"))
    w = World(); e = w.entry(T - 10, ("recognition",)); w.review(e.cards[0], T - 3, 3); w.review(e.cards[0], T, 3)
    cases.append(queue_case("qb-007", w, "reviewed today, nothing left → allDone"))
    w = World(); e = w.entry(T - 30, ("recognition",), status="excluded"); w.review(e.cards[0], T - 20, 3)
    f = w.entry(T - 5)
    cases.append(queue_case("qb-008", w, "an excluded Entry's due Card is not queued"))
    w = World()
    e = w.entry(T - 30); w.review(e.cards[0], T - 20, 3)
    f = w.entry(T - 25); w.review(f.cards[0], T - 20, 3); w.review(f.cards[0], T, 3)
    cases.append(queue_case("qb-009", w, "sibling filter: e's recall (New) is skipped because its recognition was taken in step 1; "
                                         "f's recall is skipped because f's recognition has a log today"))
    w = World(); e = w.entry(T - 30); w.review(e.cards[0], T - 1, 3)
    cases.append(queue_case("qb-010", w, "the New recall of a started Entry is taken without using the new-word limit (limit 0)", limit=0))
    write("queue-basic.json", {"kind": "queue", "source": QUEUE_SOURCE, "params": PARAMS, "cases": cases})


def queue_new_limit() -> None:
    cases = []
    w = World(); [w.entry(T - 9 + i) for i in range(5)]
    cases.append(queue_case("qn-001", w, "limit 2 counts Entries: two New Entries, one Card each", limit=2))
    w = World(); es = [w.entry(T - 9 + i) for i in range(4)]; w.review(es[0].cards[0], T, 3)
    cases.append(queue_case("qn-002", w, "an Entry introduced today counts against the limit: limit 2 → one more", limit=2))
    w = World(); es = [w.entry(T - 9 + i) for i in range(3)]; w.review(es[0].cards[0], T, 3); w.review(es[1].cards[0], T, 3)
    cases.append(queue_case("qn-003", w, "limit already used up by Entries introduced today", limit=2))
    w = World(); [w.entry(T - 9 + i) for i in range(3)]
    cases.append(queue_case("qn-004", w, "limit 0 → no New Entries", limit=0))
    w = World()
    a = w.entry(T - 5, ("recall",)); b = w.entry(T - 5, ("recognition",))
    a.created_at = b.created_at = at(T - 5, 9)
    cases.append(queue_case("qn-005", w, "same createdAt: recognition before recall"))
    write("queue-new-limit.json", {"kind": "queue", "source": QUEUE_SOURCE, "params": PARAMS, "cases": cases})


def queue_reshow() -> None:
    cases = []
    w = World(); e = w.entry(T - 20, ("recognition",)); w.review(e.cards[0], T - 10, 3); w.review(e.cards[0], T, 1)
    cases.append(queue_case("qr-001", w, "Forgot today → re-show set, counted in toReview"))
    w = World(); e = w.entry(T - 20, ("recognition",)); w.review(e.cards[0], T - 10, 3); w.review(e.cards[0], T, 1); w.review(e.cards[0], T, 3, 11)
    cases.append(queue_case("qr-002", w, "Forgot then Remembered today: the latest log decides → allDone"))
    w = World(); e = w.entry(T - 2, ("recognition",)); w.review(e.cards[0], T, 2)
    cases.append(queue_case("qr-003", w, "first-ever log rated 2 (import) → re-show"))
    w = World(); e = w.entry(T - 20, ("recognition",)); w.review(e.cards[0], T - 10, 3); w.review(e.cards[0], T, 2)
    cases.append(queue_case("qr-004", w, "rating 2 on a started Card is not a re-show"))
    w = World()
    e = w.entry(T - 20); w.review(e.cards[0], T - 10, 3); w.review(e.cards[0], T, 1)
    f = w.entry(T - 20, ("recognition",)); w.review(f.cards[0], T - 10, 3); w.review(f.cards[0], T, 1, 12)
    cases.append(queue_case("qr-005", w, "re-shows ignore the sibling filter and the quota; e's New recall is still skipped (sibling has a log today)"))
    write("queue-reshow.json", {"kind": "queue", "source": QUEUE_SOURCE, "params": PARAMS, "cases": cases})


def queue_new_answered_today() -> None:
    w = World(); es = [w.entry(T - 9 + i) for i in range(3)]
    before = queue_case("qa-001", w, "three New Entries before any answer today")
    w.review(es[0].cards[0], T, 3, 12)
    after = queue_case("qa-002", w, "the first New Card answered Remembered today: not in step 2 again, its recall is skipped "
                                     "(sibling), Due today drops by one")
    write("queue-new-answered-today.json", {"kind": "queue", "source": QUEUE_SOURCE, "params": PARAMS,
                                            "cases": [before, after]})


def backlog(w: World, n: int, started_day: int) -> None:
    for _ in range(n):
        e = w.entry(started_day - 1, ("recognition",))
        w.review(e.cards[0], started_day, 3)


def queue_catchup() -> None:
    cases = []
    w = World(); backlog(w, 150, T - 30); w.entry(T - 1)
    cases.append(queue_case("qc-001", w, "150 waiting, normalLoad 50 → catch-up, quota 50 + ceil(100/3) = 84; no new Cards"))
    w = World(); backlog(w, 130, T - 30)
    for e in w.entries[:10]:
        w.review(e.cards[0], T, 3, 8)
    cases.append(queue_case("qc-002", w, "120 waiting + 10 reviewed today = 130 → quota 77, 67 left today"))
    w = World(); backlog(w, 100, T - 30); w.entry(T - 1)
    cases.append(queue_case("qc-003", w, "load exactly 2 × normalLoad = 100 → no catch-up, all due plus new"))
    w = World()
    cards = [w.entry(T - 25, ("recognition",)) for _ in range(51)]
    for e in cards:
        w.review(e.cards[0], T - 20, 3)
        for d in range(T - 14, T):
            w.review(e.cards[0], d, 3)
    starter = w.entry(T - 16, ("recognition",)); w.review(starter.cards[0], T - 15, 3)
    cases.append(queue_case("qc-004", w, "normalLoad = 51 from the last 14 active days (T−14…T−1, 51 started reviews each); "
                                         "the 15th active day (T−15, a first review only) and T−20 are outside the window"))
    write("queue-catchup.json", {"kind": "queue", "source": QUEUE_SOURCE, "params": PARAMS, "cases": cases})


def snapshots() -> None:
    cases = []

    def add(cid, w, note, limit=10, now=NOW):
        cases.append({"id": cid, "note": note, "input": w.inputs(limit, now),
                      "expected": snapshot(w.entries, w.logs, now, OFFSET, limit)})

    add("sn-001", World(), "empty vocabulary: homeState empty, nextDueDay null")
    w = World()
    for days_ago, rating in ((1, 3), (3, 4), (5, 3), (2, 4)):
        e = w.entry(T - 30, ("recognition",)); w.review(e.cards[0], T - days_ago, rating)
    [w.entry(T - 1) for _ in range(3)]
    add("sn-002", w, "reviews falling due on different future days; New Entries limited to 2 per day", limit=2)
    w = World(); e = w.entry(T - 30, ("recognition",)); w.review(e.cards[0], T, 3)
    add("sn-003", w, "today all done; the Card falls due on T+2 → nextDueDay = T+2", limit=0)
    w = World(); e = w.entry(T - 30, ("recognition",)); w.review(e.cards[0], T - 2, 3); w.review(e.cards[0], T, 3)
    add("sn-007", w, "next review more than 6 days ahead → nextDueDay null although Entries exist", limit=0)
    w = World(); backlog(w, 150, T - 30)
    add("sn-004", w, "catch-up today: dueReviews is today's capped share (84), the remainder rolls over to following days")
    w = World(); e = w.entry(T - 20, ("recognition",)); w.review(e.cards[0], T - 10, 3); w.review(e.cards[0], T, 1)
    add("sn-005", w, "a Forgot today counts in today's dueReviews; future days assume no further answers")
    add("sn-006", World(), "generatedAt and utcOffsetMin are echoed from the input", now=at(T, 4, 0))
    write("snapshot.json", {"kind": "snapshot",
        "source": "Widget snapshot: 7 days from today; day T+k (k ≥ 1) applies the daily queue rules assuming no further answers; dueReviews = steps 1 + 3, newAvailable = step 2; nextDueDay = first of the 7 days with dueReviews + newAvailable > 0, else null; homeState = today's Home state",
        "params": PARAMS, "cases": cases})


def main(out: Path | None = None) -> None:
    global OUT
    if out is not None:
        OUT = out
    day_boundary()
    fsrs_step()
    fsrs_replay()
    queue_basic()
    queue_new_limit()
    queue_reshow()
    queue_new_answered_today()
    queue_catchup()
    snapshots()


if __name__ == "__main__":
    main()
