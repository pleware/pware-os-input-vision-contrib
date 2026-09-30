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

# A leftover bazel server holds the workspace tree on Windows, and checkout.sh is
# where that is dealt with (it stops the server, waits for the handle to go, and
# fails loudly rather than one line into a log).

./scripts/checkout.sh

# The Windows leg needs the Apple-only Swift module replaced before bazel loads
# the graph: there, rules_swift's autoconfiguration aborts the analysis of targets
# that never touch Swift (`No 'swiftc.exe' executable found in Path`), while on
# Linux the same check is only a warning. The stub is one directory in this
# repository — `swift-stub/`, whose README says why and how to extend it — and
# `.github/workflows/_wheel.yml` copies that same directory. It used to be four
# printf lines duplicated in both places, which a stub that has to grow cannot be.
# `scripts/build-local-wsl.sh` deliberately does not do this: Linux does not need it.
if [ "${OS:-}" = "Windows_NT" ]; then
  rm -rf mediapipe-src/swift-stub
  cp -r swift-stub mediapipe-src/swift-stub
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
