"""FSRS-6, day model, replay, daily queue and widget snapshot."""

import hashlib
import math
import uuid
from dataclasses import dataclass, field

W = [0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722,
     0.1666, 0.796, 1.4835, 0.0614, 0.2629, 1.6483, 0.6014, 1.8729, 0.5425,
     0.0912, 0.0658, 0.1542]
DESIRED_RETENTION = 0.90
MAX_INTERVAL = 36500
DIRECTION_ORDER = {"recognition": 0, "recall": 1, "cloze": 2}


# --- day model ---------------------------------------------------------------------------------

def day_number(t_ms: int, offset_min: int) -> int:
    return (t_ms // 1000 + offset_min * 60 - 4 * 3600) // 86400  # Python // is floor division


# --- FSRS-6 --------------------------------------------------------------------------------------

def round_half_up(x: float) -> int:
    return math.floor(x + 0.5)


def _decay(w): return -w[20]
def _factor(w): return math.pow(0.9, 1 / _decay(w)) - 1


def retrievability(t: int, s: float, w=W) -> float:
    return math.pow(1 + _factor(w) * t / s, _decay(w))


def interval(s: float, w=W, r: float = DESIRED_RETENTION) -> int:
    i = s / _factor(w) * (math.pow(r, 1 / _decay(w)) - 1)
    return min(max(round_half_up(i), 1), MAX_INTERVAL)


def _d0(g: int, w) -> float:
    return w[4] - math.exp(w[5] * (g - 1)) + 1


def _clamp(x: float, lo: float, hi: float) -> float:
    return min(max(x, lo), hi)


def fuzz_seed(card_id: str, reps: int) -> float:
    digest = hashlib.sha256(uuid.UUID(card_id).bytes + reps.to_bytes(4, "big")).digest()
    return (int.from_bytes(digest[:8], "big") >> 11) / float(1 << 53)


def fuzz(ivl: int, card_id: str, reps: int) -> int:
    if ivl < 3:
        return ivl
    delta = 1.0
    for start, end, f in ((2.5, 7.0, 0.15), (7.0, 20.0, 0.10), (20.0, math.inf, 0.05)):
        delta += f * max(0.0, min(ivl, end) - start)
    lo = max(2, round_half_up(ivl - delta))
    hi = min(round_half_up(ivl + delta), MAX_INTERVAL)
    return lo + math.floor(fuzz_seed(card_id, reps) * (hi - lo + 1))


@dataclass
class CardState:
    stability: float
    difficulty: float
    last_review_day: int
    due_day: int
    reps: int
    lapses: int
    last_rating: int
    interval: int | None  # pre-fuzz interval of the last step; None when due = review day

    @property
    def stage(self) -> str:
        return "known_well" if self.stability >= 21 and self.last_rating != 1 else "learning"


def step(state: CardState | None, card_id: str, day: int, g: int, w=W, r=DESIRED_RETENTION) -> CardState:
    assert g in (1, 2, 3, 4)
    if state is None:
        s_new, d_new, reps, lapses = w[g - 1], _clamp(_d0(g, w), 1, 10), 1, 0
    else:
        s, d = state.stability, state.difficulty
        t = max(0, day - state.last_review_day)
        d_prime = d + (-w[6] * (g - 3)) * (10 - d) / 9
        d_new = _clamp(w[7] * _d0(4, w) + (1 - w[7]) * d_prime, 1, 10)
        if t == 0:
            inc = math.exp(w[17] * (g - 3 + w[18])) * math.pow(s, -w[19])
            if g >= 2:  # as py-fsrs 6.3.3: the same-day floor applies to Hard, Good and Easy
                inc = max(inc, 1.0)
            s_new = s * inc
        else:
            rr = retrievability(t, s, w)
            if g >= 2:
                hard = w[15] if g == 2 else 1
                easy = w[16] if g == 4 else 1
                s_new = s * (math.exp(w[8]) * (11 - d) * math.pow(s, -w[9])
                             * (math.exp(w[10] * (1 - rr)) - 1) * hard * easy + 1)
            else:
                sf = w[11] * math.pow(d, -w[12]) * (math.pow(s + 1, w[13]) - 1) * math.exp(w[14] * (1 - rr))
                s_new = min(sf, s / math.exp(w[17] * w[18]))
        reps, lapses = state.reps + 1, state.lapses + (1 if g == 1 else 0)
    s_new = _clamp(s_new, 0.001, 36500)
    if g == 1 or (state is None and g == 2):
        due, ivl = day, None
    else:
        ivl = interval(s_new, w, r)
        due = day + fuzz(ivl, card_id, reps)
    return CardState(s_new, d_new, day, due, reps, lapses, g, ivl)


# --- replay ------------------------------------------------------------------------------------

@dataclass(frozen=True)
class Log:
    id: str
    card_id: str
    reviewed_at: int
    utc_offset_min: int
    rating: int | None

    @property
    def day(self) -> int:
        return day_number(self.reviewed_at, self.utc_offset_min)

    def sort_key(self):
        return self.reviewed_at, uuid.UUID(self.id).bytes


def replay(card_id: str, logs: list[Log], w=W, r=DESIRED_RETENTION) -> CardState | None:
    state = None
    for log in sorted(logs, key=Log.sort_key):
        if log.rating is not None:
            state = step(state, card_id, log.day, log.rating, w, r)
    return state


# --- daily queue and snapshot -------------------------------------------------------------------

@dataclass
class Card:
    id: str
    direction: str


@dataclass
class Entry:
    id: str
    created_at: int
    status: str = "active"
    cards: list[Card] = field(default_factory=list)


@dataclass
class Queue:
    reviews: list[str]
    new: list[str]
    reshow: list[str]
    waiting: int
    catch_up: bool
    normal_load: int
    home_state: str


def _id_bytes(i: str) -> bytes:
    return uuid.UUID(i).bytes


def build_queue(entries: list[Entry], logs: list[Log], today: int, new_words_per_day: int) -> Queue:
    live = entries  # fixtures contain live (not deleted) Entries only
    active = [e for e in live if e.status == "active" and e.cards]
    card_entry = {c.id: e for e in active for c in e.cards}
    rated = [l for l in logs if l.rating is not None and l.card_id in card_entry]
    by_card: dict[str, list[Log]] = {}
    for l in rated:
        by_card.setdefault(l.card_id, []).append(l)
    states = {cid: replay(cid, ls) for cid, ls in by_card.items()}

    def has_before(cid, day): return any(l.day < day for l in by_card.get(cid, []))
    def logs_on(cid, day): return [l for l in by_card.get(cid, []) if l.day == day]

    cards = [c for e in active for c in e.cards]
    started = {c.id for c in cards if has_before(c.id, today)}
    reviewed_today = {cid for cid in started if logs_on(cid, today)}
    waiting = [cid for cid in started if not logs_on(cid, today) and states[cid].due_day <= today]
    entry_new = {e.id: not any(has_before(c.id, today) for c in e.cards) for e in active}
    introduced_today = {e.id for e in active if entry_new[e.id] and any(logs_on(c.id, today) for c in e.cards)}

    reshow = []
    for c in cards:
        todays = sorted(logs_on(c.id, today), key=Log.sort_key)
        if todays:
            st = replay(c.id, [l for l in by_card[c.id] if l.sort_key() <= todays[-1].sort_key()])
            if st.due_day == today:
                reshow.append(c.id)
    reshow.sort(key=_id_bytes)

    days_with_logs = sorted({l.day for l in rated if l.day < today}, reverse=True)[:14]
    pairs = {(l.card_id, l.day) for l in rated if l.day in days_with_logs and has_before(l.card_id, l.day)}
    normal_load = 50 if not days_with_logs else max(50, math.ceil(len(pairs) / len(days_with_logs)))
    load = len(waiting) + len(reviewed_today)
    catch_up = load > 2 * normal_load
    quota = normal_load + math.ceil((load - normal_load) / 3) if catch_up else math.inf

    taken: list[str] = []
    taken_entries: set[str] = set()
    entries_with_log_today = {card_entry[l.card_id].id for l in rated if l.day == today}

    def passes(cid: str) -> bool:
        eid = card_entry[cid].id
        return eid not in entries_with_log_today and eid not in taken_entries

    def take(cid: str):
        taken.append(cid)
        taken_entries.add(card_entry[cid].id)

    reviews: list[str] = []
    limit = max(0, quota - len(reviewed_today))
    order = sorted(waiting, key=lambda cid: (retrievability(today - states[cid].last_review_day, states[cid].stability),
                                             states[cid].due_day, _id_bytes(cid)))
    for cid in order:
        if len(reviews) >= limit:
            break
        if passes(cid):
            take(cid)
            reviews.append(cid)

    new: list[str] = []
    if not catch_up:
        new_entries_taken = 0
        candidates = [(e, c) for e in active for c in e.cards if c.id not in by_card or
                      (not has_before(c.id, today) and not logs_on(c.id, today))]
        candidates.sort(key=lambda ec: (ec[0].created_at, DIRECTION_ORDER[ec[1].direction], _id_bytes(ec[1].id)))
        for e, c in candidates:
            if not passes(c.id):
                continue
            if entry_new[e.id]:
                if len(introduced_today) + new_entries_taken < new_words_per_day:
                    take(c.id)
                    new.append(c.id)
                    new_entries_taken += 1
            else:
                take(c.id)
                new.append(c.id)

    if not live:
        home = "empty"
    elif not active and any(not e.cards for e in live):
        home = "noneReviewable"
    elif reviews or new or reshow:
        home = "due"
    elif any(l.day == today for l in rated):
        home = "allDone"
    else:
        home = "nothingDue"
    return Queue(reviews, new, reshow, len(waiting), catch_up, normal_load, home)


def snapshot(entries: list[Entry], logs: list[Log], now: int, offset_min: int, new_words_per_day: int) -> dict:
    today = day_number(now, offset_min)
    days, home = [], None
    for k in range(7):
        q = build_queue(entries, logs, today + k, new_words_per_day)
        if k == 0:
            home = q.home_state
        days.append({"day": today + k, "dueReviews": len(q.reviews) + len(q.reshow), "newAvailable": len(q.new)})
    next_due = next((d["day"] for d in days if d["dueReviews"] + d["newAvailable"] > 0), None)
    return {"format": 1, "generatedAt": now, "utcOffsetMin": offset_min, "days": days,
            "nextDueDay": next_due, "homeState": home}
