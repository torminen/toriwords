"""Field comparator and envelope merge."""

import uuid


def wins(a: dict, b: dict) -> bool:
    return (a["u"], a["c"]) > (b["u"], b["c"])


def merge_field(local: dict, remote: dict) -> dict:
    return remote if wins(remote, local) else local


def merge_envelope(local: dict, remote: dict) -> dict:
    deleted = local["deleted"] or remote["deleted"]
    into = [m for m in (local["mergedInto"], remote["mergedInto"]) if m is not None]
    merged_into = min(into, key=lambda i: uuid.UUID(i).bytes) if into else None
    fields: dict = {}
    if not deleted:
        for name in sorted(set(local["fields"]) | set(remote["fields"])):
            a, b = local["fields"].get(name), remote["fields"].get(name)
            fields[name] = a if b is None else b if a is None else merge_field(a, b)
    return {"id": local["id"], "type": local["type"], "schema": max(local["schema"], remote["schema"]),
            "owner": local["owner"], "deleted": deleted, "mergedInto": merged_into, "fields": fields}
