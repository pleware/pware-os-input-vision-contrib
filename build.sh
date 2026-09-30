#!/usr/bin/env bash
# Builds the telemetry-free mediapipe wheel with the workspace-pinned toolchain.
#
# Prereq: `ignite bootstrap` in pware-os-workspace (or
# `sh <kit>/ensure.sh <pware-os-workspace>`), so bazel 7.4.1, python 3.12 and
# mise are on PATH — see ../mise.toml.
#
# `mise run setup-system` installs the platform system deps mise cannot pin:
# MSVC (winget) on Windows, OpenCV codecs (apt) on Linux. Idempotent.
set -euo pipefail

mise run setup-system

# A leftover bazel server holds the workspace tree on Windows, and then
# `rm -rf mediapipe-src` (the first thing checkout.sh does) dies with
# `Device or resource busy` before a single line compiles. The server that owns
# the workspace is the one to stop, and `bazel shutdown` has to run from inside
# it — which is why this lives here rather than in checkout.sh, which is about to
# delete that directory. CI never meets this: every run gets a fresh runner.
if [ -d mediapipe-src ]; then
  (cd mediapipe-src && bazel shutdown >/dev/null 2>&1) || true
fi

./scripts/checkout.sh

# The Windows leg needs the Swift module stubbed before bazel looks at it: on
# Windows `rules_swift`'s autoconfiguration aborts the analysis of targets that
# never touch Swift (`No 'swiftc.exe' executable found in Path`), while on Linux
# the same check is only a warning. `_wheel.yml` carries the CI twin of this step;
# `scripts/build-local-wsl.sh` deliberately does not, because it does not need it.
if [ "${OS:-}" = "Windows_NT" ]; then
  mkdir -p mediapipe-src/swift-stub
  printf 'module(name = "rules_swift", version = "2.3.0")\n' > mediapipe-src/swift-stub/MODULE.bazel
  printf 'common --override_module=rules_swift=%s/swift-stub\n' \
    "$(cygpath -m "$PWD/mediapipe-src")" >> mediapipe-src/.bazelrc
fi

cd mediapipe-src
python -m pip install --upgrade setuptools wheel
python setup.py bdist_wheel
cd ..

# The gate, locally: the wheel must carry none of the markers Google's own
# wheels carry (`scripts/scan-wheel.py`).
python scripts/scan-wheel.py --dir mediapipe-src/dist > telemetry-scan.json
echo "wheel: $(ls mediapipe-src/dist/*.whl)"
echo "scan:  telemetry-scan.json"
