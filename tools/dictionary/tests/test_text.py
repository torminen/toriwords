import pytest

from conftest import cases
from toridict.text import clean, clean_ru, match_key, search_fold


@pytest.mark.parametrize("cid,case", cases("normalization/match-key.json") + cases("normalization/translation-key.json"))
def test_match_key_fixture(cid, case):
    assert match_key(case["input"]) == case["expected"]


@pytest.mark.parametrize("cid,case", cases("normalization/search-fold.json"))
def test_search_fold_fixture(cid, case):
    assert search_fold(case["input"]) == case["expected"]


def test_clean_maps_quotes_dashes_and_strips_markup():
    assert clean("a [[b|c]] ‘d’ — ''e'' {{tpl}}<sup>x</sup>­  f") == "a c 'd' - e x f"


def test_clean_ru_removes_stress_but_keeps_yo_and_short_i():
    assert clean_ru("бе́гать ёж й") == "бегать ёж й"
