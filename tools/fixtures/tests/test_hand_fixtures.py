"""The hand-written fixtures and the Python reference must agree (each catches mistakes in the other)."""

import pytest

from conftest import cases, load
from torifix import capture, hlc, ids, merge, text

TEXT_FUNCTIONS = {"matchKey": text.match_key, "translationKey": text.translation_key, "sentenceKey": text.sentence_key,
                  "tagKey": text.tag_key, "searchFold": text.search_fold, "urlKey": text.url_key}
TEXT_FILES = ["match-key", "translation-key", "sentence-key", "tag-key", "search-fold", "url-key"]


@pytest.mark.parametrize("rel,case", [(f"normalization/{f}.json", c) for f in TEXT_FILES
                                      for _, c in cases(f"normalization/{f}.json")], ids=lambda x: x if isinstance(x, str) else x["id"])
def test_text_keys(rel, case):
    fn = TEXT_FUNCTIONS[load(rel)["function"]]
    assert fn(case["input"]) == case["expected"]


@pytest.mark.parametrize("cid,case", cases("normalization/source-key.json"))
def test_source_key(cid, case):
    i = case["input"]
    assert text.source_key(i["title"], i["app"], i["kind"]) == case["expected"]


@pytest.mark.parametrize("cid,case", cases("normalization/text-order.json"))
def test_text_order(cid, case):
    ordered = sorted(case["keys"], key=lambda s: s.encode("utf-8"))
    if "prefix" in case:
        p = case["prefix"].encode("utf-8")
        ordered = [k for k in ordered if p <= k.encode("utf-8") < p + b"\xff\xff"]
    assert ordered == case["expected"]


@pytest.mark.parametrize("cid,case", cases("ids/uuid-v5.json"))
def test_uuid_v5(cid, case):
    assert load("ids/uuid-v5.json")["namespace"] == str(ids.NAMESPACE)
    assert ids.v5(case["name"]) == case["uuid"]


@pytest.mark.parametrize("cid,case", cases("ids/uuid-v7.json"))
def test_uuid_v7(cid, case):
    assert ids.v7(case["unixMs"], int(case["randA"], 16), int(case["randB"], 16)) == case["uuid"]


@pytest.mark.parametrize("cid,case", cases("ids/byte-order.json"))
def test_byte_order(cid, case):
    if "a" in case:
        assert ids.compare(case["a"], case["b"]) == case["expected"]
        assert (case["a"] > case["b"]) - (case["a"] < case["b"]) == case["expected"]  # lowercase hex string order agrees
    else:
        import functools
        assert sorted(case["input"], key=functools.cmp_to_key(ids.compare)) == case["expected"]


@pytest.mark.parametrize("cid,case", cases("hlc/local-write.json"))
def test_hlc_local_write(cid, case):
    ms, c = hlc.local_write(case["state"]["ms"], case["state"]["counter"], case["now"])
    assert {"ms": ms, "counter": c} == case["expected"]["state"]
    assert hlc.fmt(ms, c, load("hlc/local-write.json")["node"]) == case["expected"]["clock"]


@pytest.mark.parametrize("cid,case", cases("hlc/receive.json"))
def test_hlc_receive(cid, case):
    if case["type"] == "serverSkew":
        ok = hlc.server_accepts(case["clock"], case["serverTime"])
        assert ("accepted" if ok else "clock_skew") == case["expected"]["result"]
    else:
        ms, c = hlc.receive(case["state"]["ms"], case["state"]["counter"], case["remote"], case["now"])
        assert {"ms": ms, "counter": c} == case["expected"]["state"]


@pytest.mark.parametrize("cid,case", cases("hlc/clock-ahead.json"))
def test_hlc_clock_ahead(cid, case):
    node = load("hlc/clock-ahead.json")["node"]
    reset, ms, c = hlc.clock_ahead_reset(case["state"]["ms"], case["state"]["counter"], case["lastServerTime"], case["now"])
    clocks = []
    if reset:
        for _ in range(case["pendingFields"]):
            ms, c = hlc.local_write(ms, c, case["now"])
            clocks.append(hlc.fmt(ms, c, node))
    assert case["expected"] == {"reset": reset, "state": {"ms": ms, "counter": c}, "restampedClocks": clocks}


@pytest.mark.parametrize("cid,case", cases("merge/field-comparator.json"))
def test_field_comparator(cid, case):
    winner = merge.merge_field(case["local"], case["remote"])
    assert winner is (case["local"] if case["expected"] == "local" else case["remote"])


@pytest.mark.parametrize("cid,case", cases("merge/envelope.json"))
def test_envelope(cid, case):
    assert merge.merge_envelope(case["local"], case["remote"]) == case["expected"]
    assert merge.merge_envelope(case["remote"], case["local"]) == case["expected"]
    if "remotePartial" in case:
        assert merge.merge_envelope(case["local"], case["remotePartial"]) == case["expected"]


@pytest.mark.parametrize("cid,case", cases("capture/clean.json"))
def test_capture_clean(cid, case):
    cleaned, _ = capture.clean(case["input"])
    assert {"text": cleaned, "kind": capture.classify(cleaned), "saveable": capture.saveable(cleaned)} == case["expected"]


@pytest.mark.parametrize("cid,case", cases("capture/extract.json"))
def test_capture_extract(cid, case):
    first, last = case["chosenChips"]
    assert capture.extract(case["input"], first, last) == case["expected"]
    assert len(case["expected"]["sentence"]) <= capture.MAX_SENTENCE


@pytest.mark.parametrize("cid,case", cases("capture/typed-highlight.json"))
def test_capture_typed_highlight(cid, case):
    assert capture.typed_highlight(case["sentence"], case["entryText"]) == case["expected"]
