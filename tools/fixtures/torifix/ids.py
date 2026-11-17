"""IDs, doc 36 §11.2."""

import uuid

NAMESPACE = uuid.UUID("6f1c2a4e-3b7d-5e59-9a0c-5d8e7f2b1c34")


def v5(name: str) -> str:
    return str(uuid.uuid5(NAMESPACE, name))


def v7(unix_ms: int, rand_a: int, rand_b: int) -> str:
    """RFC 9562 layout: 48-bit ms | ver 7 | 12-bit rand_a | variant 0b10 | 62-bit rand_b."""
    assert 0 <= unix_ms < 1 << 48 and 0 <= rand_a < 1 << 12 and 0 <= rand_b < 1 << 62
    value = (unix_ms << 80) | (0x7 << 76) | (rand_a << 64) | (0b10 << 62) | rand_b
    return str(uuid.UUID(int=value))


def compare(a: str, b: str) -> int:
    x, y = uuid.UUID(a).bytes, uuid.UUID(b).bytes
    return (x > y) - (x < y)
