#!/usr/bin/env bash
# Clones the pinned mediapipe source commit into ./mediapipe-src.
set -euo pipefail

commit=$(awk '/^commit/{print $3}' mediapipe.pin)
[ -n "$commit" ] || { echo "no commit in mediapipe.pin" >&2; exit 1; }

rm -rf mediapipe-src
git clone --filter=blob:none --no-checkout \
  https://github.com/google-ai-edge/mediapipe mediapipe-src
git -C mediapipe-src checkout "$commit"
echo "mediapipe source at $commit"
