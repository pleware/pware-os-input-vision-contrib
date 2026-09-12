#!/usr/bin/env bash
# Clones the pinned mediapipe source commit into ./mediapipe-src, tags the
# build with the pinned version, and applies the source patches below.
#
# Patches (all for face/vision only — we do not ship LLM inference, OpenCV
# file/video I/O, or on-device codecs):
# 1. Drop the LLM (genai) deps whose `@odml` repo is undefined in this release.
# 2. Turn off OpenCV codecs whose system libraries are gone/renamed on modern
#    distros (OpenEXR 2.x, FFmpeg avresample, GStreamer).
# 3. Drop the same libs from the static `linkopts` list — that hardcoded list is
#    what actually breaks the link on a modern system, independent of #2.
# 4. Normalize CRLF (a CRLF checkout on Windows breaks --noenable_bzlmod).
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

# 3. Drop the same libs from the static linkopts list (the hardcoded list is
#    what actually fails to link on a modern system).
sed -i \
  -e '/"-lImath",/d' -e '/"-lIlmImf",/d' -e '/"-lIex",/d' \
  -e '/"-lHalf",/d' -e '/"-lIlmThread",/d' -e '/"-ldc1394",/d' \
  -e '/"-lavcodec",/d' -e '/"-lavformat",/d' -e '/"-lavutil",/d' \
  -e '/"-lswscale",/d' -e '/"-lavresample",/d' \
  mediapipe-src/third_party/BUILD

# 4. A CRLF checkout on Windows breaks `--noenable_bzlmod` in .bazelrc.
sed -i 's/\r$//' mediapipe-src/.bazelrc mediapipe-src/.bazelversion

# 5. The zlib http_archive points at zlib.net over HTTP, which flakes in CI.
#    Add a GitHub mirror (same file, same sha256) as a fallback URL.
sed -i 's|url = "http://zlib.net/fossils/zlib-1.2.13.tar.gz",|urls = ["http://zlib.net/fossils/zlib-1.2.13.tar.gz", "https://github.com/madler/zlib/releases/download/v1.2.13/zlib-1.2.13.tar.gz"],|' \
  mediapipe-src/WORKSPACE

echo "mediapipe source at $commit (version $version, patched)"
