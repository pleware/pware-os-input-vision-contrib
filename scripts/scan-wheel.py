#!/usr/bin/env python3
"""Scan a built mediapipe wheel for Google's clearcut uploader, and fail if it
is there.

This is the gate that makes "telemetry-free" a property of the artifact instead
of a claim in a README. Google's pip wheels carry the uploader inside their
native library — measured, not assumed: 0.10.35 carries 62 `clearcut` strings,
1.0.0 and 1.0.1 carry 66, each naming `https://play.googleapis.com/log`, while
the open-source tree we build from names clearcut nowhere (verified at both
v0.10.35 and v1.0.0, 5 4xx paths scanned, zero matches). A wheel that comes out
of `setup.py bdist_wheel` here must therefore carry none of it; if one does, the
build is not what we think it is and nothing downstream should install it.

Usage:  scan-wheel.py dist/*.whl        # one or more wheels
        scan-wheel.py --dir dist        # every wheel in a directory

Exit status: 0 when every wheel is clean, 1 on a marker or on finding no
library at all (a wheel we cannot inspect is not a wheel we can vouch for).
A JSON manifest goes to stdout so CI can keep it beside the artifact.
"""

from __future__ import annotations

import argparse
import glob
import json
import os
import sys
import zipfile

# The four markers, checked case-insensitively. The first is the service, the
# second is the endpoint literal, the last two are the class and the proto
# logger that G.R.I.M's audit uses as its forbidden set.
MARKERS = (
    b"clearcut",
    b"play.googleapis.com",
    b"clearcutloggingclient",
    b"tasksstatsprotologger",
)

LIBRARY_SUFFIXES = (".dll", ".so", ".dylib")


def libraries(wheel: str) -> list[str]:
    """The native libraries inside the wheel, under mediapipe/."""
    with zipfile.ZipFile(wheel) as z:
        return [
            name
            for name in z.namelist()
            if name.startswith("mediapipe/")
            and name.lower().endswith(LIBRARY_SUFFIXES)
        ]


def scan(wheel: str) -> dict:
    names = libraries(wheel)
    counts: dict[str, dict[str, int]] = {}
    with zipfile.ZipFile(wheel) as z:
        for name in names:
            blob = z.read(name).lower()
            counts[name] = {
                marker.decode(): blob.count(marker) for marker in MARKERS
            }
    dirty = {
        name: {m: n for m, n in per.items() if n}
        for name, per in counts.items()
        if any(per.values())
    }
    return {
        "wheel": os.path.basename(wheel),
        "bytes": os.path.getsize(wheel),
        "libraries": names,
        "counts": counts,
        "clean": not dirty and bool(names),
        "found": dirty,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("wheels", nargs="*", help="wheel paths")
    parser.add_argument("--dir", help="scan every *.whl in this directory")
    args = parser.parse_args()

    paths = list(args.wheels)
    if args.dir:
        paths += sorted(glob.glob(os.path.join(args.dir, "*.whl")))
    if not paths:
        parser.error("no wheels given (pass paths, or --dir)")

    manifests = []
    for path in paths:
        if not os.path.exists(path):
            print(f"FAIL: {path} does not exist — nothing to vouch for", file=sys.stderr)
            return 1
        manifests.append(scan(path))
    print(json.dumps(manifests, indent=2))

    failed = False
    for manifest in manifests:
        if not manifest["libraries"]:
            print(
                f"FAIL: {manifest['wheel']} carries no mediapipe native library — "
                "a wheel we cannot inspect is not one we can vouch for",
                file=sys.stderr,
            )
            failed = True
        for name, found in manifest["found"].items():
            print(
                f"FAIL: {manifest['wheel']} :: {name} carries Google's uploader "
                f"{found} — the build is not from the clean source",
                file=sys.stderr,
            )
            failed = True
        if manifest["clean"]:
            print(f"ok: {manifest['wheel']} — no clearcut, no endpoint", file=sys.stderr)

    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
