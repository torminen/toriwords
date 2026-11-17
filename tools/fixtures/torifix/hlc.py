"""Hybrid logical clock, doc 36 §11.3 and §11.5 step 2."""

MAX_COUNTER = 0xFFFF
DAY_MS = 86_400_000
HOUR_MS = 3_600_000


def fmt(ms: int, counter: int, node: str) -> str:
    return f"{ms:012x}{counter:04x}{node}"


def parse(clock: str) -> tuple[int, int, str]:
    return int(clock[:12], 16), int(clock[12:16], 16), clock[16:]


def _bump(ms: int, counter: int) -> tuple[int, int]:
    return (ms + 1, 0) if counter > MAX_COUNTER else (ms, counter)


def local_write(ms: int, counter: int, now: int) -> tuple[int, int]:
    if now > ms:
        return now, 0
    return _bump(ms, counter + 1)


def receive(ms: int, counter: int, remote: str, now: int) -> tuple[int, int]:
    r_ms, r_counter, _ = parse(remote)
    if r_ms - now > DAY_MS:
        return ms, counter  # not adopted; the record is still stored
    new_ms = max(ms, r_ms, now)
    if new_ms == ms and new_ms == r_ms:
        c = max(counter, r_counter) + 1
    elif new_ms == ms:
        c = counter + 1
    elif new_ms == r_ms:
        c = r_counter + 1
    else:
        c = 0
    return _bump(new_ms, c)


def clock_ahead_reset(ms: int, counter: int, last_server_time: int, now: int) -> tuple[bool, int, int]:
    if ms - last_server_time > HOUR_MS:
        return True, max(last_server_time, now), 0
    return False, ms, counter


def server_accepts(clock: str, server_time: int) -> bool:
    return parse(clock)[0] - server_time <= HOUR_MS
