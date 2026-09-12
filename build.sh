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

./scripts/checkout.sh
cd mediapipe-src
python -m pip install --upgrade setuptools wheel
python setup.py bdist_wheel
echo "wheel: $(ls dist/*.whl)"
