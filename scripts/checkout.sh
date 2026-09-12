#!/usr/bin/env bash
# Clones the pinned mediapipe source commit into ./mediapipe-src, tags the
# build with the pinned version, and applies two source patches:
#
# 1. Drops the LLM (genai) deps we do not ship. The tasks C binary links
#    genai/bundler + genai/converter unconditionally, but their `@odml`
#    dependency is not defined in this release's WORKSPACE and we ship
#    face/vision, not on-device LLM inference.
# 2. Turns off the OpenCV codecs whose system libraries are gone or renamed on
#    modern distros (OpenEXR 2.x names, FFmpeg avresample, GStreamer). We ship
#    a NumPy-driven API, not OpenCV file/video I/O, so they are not needed.
set -euo pipefail

commit=$(awk '/^commit/{print $3}' mediapipe.pin)
version=$(awk '/^version/{print $3}' mediapipe.pin)
[ -n "$commit" ] || { echo "no commit in mediapipe.pin" >&2; exit 1; }
[ -n "$version" ] || { echo "no version in mediapipe.pin" >&2; exit 1; }

rm -rf mediapipe-src
git clone --filter=blob:none --no-checkout \
  https://github.com/google-ai-edge/mediapipe mediapipe-src
git -C mediapipe-src checkout "$commit"
sed -i "s/__version__ = 'dev'/__version__ = '$version'/" mediapipe-src/setup.py

# 1. Drop the LLM deps (their @odml repo is undefined in this release).
sed -i \
  -e '/genai\/bundler:llm_bundler_utils_c_lib/d' \
  -e '/genai\/converter:llm_converter_c_lib/d' \
  mediapipe-src/mediapipe/tasks/c/BUILD

# 2. Disable OpenCV codecs that are gone/renamed on modern distros.
sed -i 's/"WITH_WEBP": "OFF",/"WITH_WEBP": "OFF",\n        "WITH_OPENEXR": "OFF",\n        "WITH_FFMPEG": "OFF",\n        "WITH_GSTREAMER": "OFF",/' \
  mediapipe-src/third_party/BUILD

# 3. A CRLF checkout on Windows breaks `--noenable_bzlmod` in .bazelrc (Bazel
# reads the trailing \r and leaves bzlmod on, which then cannot see WORKSPACE
# repos). Normalize the files Bazel parses.
sed -i 's/\r$//' mediapipe-src/.bazelrc mediapipe-src/.bazelversion

echo "mediapipe source at $commit (version $version, genai + codecs dropped)"
