"""Our FSRS-6 parameters and formulas agree with the pinned py-fsrs release."""

import math

import pytest
from fsrs import Rating, Scheduler
from fsrs.scheduler import DEFAULT_PARAMETERS

from conftest import cases
from torifix.scheduler import W, retrievability

REF = Scheduler(desired_retention=0.9, learning_steps=(), relearning_steps=(), maximum_interval=36500, enable_fuzzing=False)


def test_default_parameters_match_py_fsrs():
    assert list(DEFAULT_PARAMETERS) == W


def close(a: float, b: float) -> bool:
    return math.isclose(a, b, rel_tol=1e-12)


@pytest.mark.parametrize("cid,case", cases("scheduler/fsrs-step.json"))
def test_step_matches_py_fsrs(cid, case):
    g, exp, prev = Rating(case["rating"]), case["expected"], case["state"]
    if prev is None:
        s = REF._initial_stability(rating=g)
        d = REF._initial_difficulty(rating=g, clamp=True)
    else:
        t = max(0, case["reviewDay"] - prev["lastReviewDay"])
        d = REF._next_difficulty(difficulty=prev["difficulty"], rating=g)
        if t == 0:
            s = REF._short_term_stability(stability=prev["stability"], rating=g)
        else:
            r = retrievability(t, prev["stability"])
            s = REF._next_stability(difficulty=prev["difficulty"], stability=prev["stability"], retrievability=r, rating=g)
    s = min(max(s, 0.001), 36500)
    assert close(s, exp["stability"]) and close(d, exp["difficulty"])
    if exp["interval"] is not None:
        # py-fsrs rounds half to even; ours rounds half up. They agree unless I lands exactly on .5.
        assert abs(REF._next_interval(stability=s) - exp["interval"]) <= 1
