import filecmp

import generate
from conftest import FIXTURES


def test_generation_is_deterministic_and_committed_files_are_current(tmp_path):
    first, second = tmp_path / "a", tmp_path / "b"
    generate.main(first)
    generate.main(second)
    names = sorted(p.name for p in first.iterdir())
    assert names == sorted(p.name for p in second.iterdir())
    committed = FIXTURES / "scheduler"
    for name in names:
        assert (first / name).read_bytes() == (second / name).read_bytes(), name
        assert filecmp.cmp(first / name, committed / name, shallow=False), f"{name} is stale: run generate.py"
