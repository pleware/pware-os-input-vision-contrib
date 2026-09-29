#!/usr/bin/env bash
# Clones the pinned mediapipe source commit into ./mediapipe-src, stamps the
# build with the pinned version, and applies the source patches below.
#
# Every patch asserts the anchor it edits still exists and fails loudly when it
# does not. That is the lesson from the 0.10.35 -> v1.0.0 move: three of these
# patches had quietly stopped matching, so the recipe "worked" while doing
# nothing (and the run that followed blamed bazel). A silent `sed` is a lie with
# a zero exit status.
#
# Patches (all for face/vision only — we do not ship LLM inference, OpenCV
# file/video I/O, or on-device codecs):
# 1. Turn off OpenCV codecs whose system libraries are gone/renamed on modern
#    distros (OpenEXR 2.x, FFmpeg avresample, GStreamer).
# 2. Drop the same libs from the static `linkopts` list — that hardcoded list is
#    what actually breaks the link on a modern system, independent of #1.
# 3. Normalize CRLF: mediapipe's own `.bazelrc` lines are read by bazel before
#    anything of ours runs, and a CRLF checkout on Windows breaks them.
#
# Gone since 0.10.35, and deliberately not carried forward:
# - dropping the LLM (genai) deps — v1.0.0's `mediapipe/tasks/c/BUILD` no longer
#   names them;
# - the zlib http_archive mirror — v1.0.0 does not fetch zlib from zlib.net
#   over HTTP any more (bzlmod, `MODULE.bazel`).
set -euo pipefail

pin_value() { awk -v key="$1" '$1 == key {print $3}' mediapipe.pin; }

commit=$(pin_value commit)
version=$(pin_value version)
[ -n "$commit" ] || { echo "no commit in mediapipe.pin" >&2; exit 1; }
[ -n "$version" ] || { echo "no version in mediapipe.pin" >&2; exit 1; }

rm -rf mediapipe-src
git clone --filter=blob:none --no-checkout \
  https://github.com/google-ai-edge/mediapipe mediapipe-src
git -C mediapipe-src checkout "$commit"

# The wheel's version comes from setup.py, which ships as 'dev'; the pin is the
# one place the version lives.
grep -q "__version__ = 'dev'" mediapipe-src/setup.py || {
  echo "setup.py no longer carries __version__ = 'dev' — the pin cannot stamp it" >&2
  exit 1
}
sed -i "s/__version__ = 'dev'/__version__ = '$version'/" mediapipe-src/setup.py

# Assert an anchor exists, then apply. `sed` on a missing anchor is a no-op that
# exits 0 — the exact failure this guards.
apply() {
  local file="$1" anchor="$2"
  shift 2
  grep -q "$anchor" "$file" || {
    echo "anchor gone: '$anchor' not in $file — the patch below no longer applies" >&2
    exit 1
  }
  sed -i "$@" "$file"
}

# 1. Disable OpenCV codecs that are gone/renamed on modern distros.
apply mediapipe-src/third_party/BUILD '"WITH_WEBP": "OFF",' \
  's/"WITH_WEBP": "OFF",/"WITH_WEBP": "OFF",\n        "WITH_OPENEXR": "OFF",\n        "WITH_FFMPEG": "OFF",\n        "WITH_GSTREAMER": "OFF",/'

# 2. Drop the same libs from the static linkopts list (the hardcoded list is what
#    actually fails to link on a modern system).
apply mediapipe-src/third_party/BUILD '"-lImath",' \
  -e '/"-lImath",/d' -e '/"-lIlmImf",/d' -e '/"-lIex",/d' \
  -e '/"-lHalf",/d' -e '/"-lIlmThread",/d' -e '/"-ldc1394",/d' \
  -e '/"-lavcodec",/d' -e '/"-lavformat",/d' -e '/"-lavutil",/d' \
  -e '/"-lswscale",/d' -e '/"-lavresample",/d'

# 3. A CRLF checkout breaks mediapipe's own .bazelrc on Windows (and with it
#    bzlmod, which v1.0.0 turns on there).
sed -i 's/\r$//' mediapipe-src/.bazelrc mediapipe-src/.bazelversion

echo "mediapipe source at $commit (version $version, patched)"
