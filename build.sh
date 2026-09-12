#!/usr/bin/env bash
# Builds the telemetry-free mediapipe wheel with the workspace-pinned toolchain.
#
# Prereq: `ignite bootstrap` in pware-os-workspace (or
# `sh <kit>/ensure.sh <pware-os-workspace>`), so bazel 7.4.1 and python 3.12
# from that workspace's mise.toml are on PATH. See ../mise.toml.
set -euo pipefail

./scripts/checkout.sh
cd mediapipe-src
python -m pip install --upgrade setuptools wheel
python setup.py bdist_wheel
echo "wheel: $(ls dist/*.whl)"
