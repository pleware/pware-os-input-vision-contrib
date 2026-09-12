#!/usr/bin/env bash
# Clones the pinned mediapipe source commit into ./mediapipe-src, tags the
# build with the pinned version, and drops the LLM (genai) deps we do not ship.
#
# A raw checkout reports __version__ = 'dev', which modern setuptools rejects.
# The tasks C binary links genai/bundler + genai/converter unconditionally, but
# their `@odml` dependency is not defined in this release's WORKSPACE and we do
# not ship on-device LLM inference — so those two deps are removed.
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
sed -i \
  -e '/genai\/bundler:llm_bundler_utils_c_lib/d' \
  -e '/genai\/converter:llm_converter_c_lib/d' \
  mediapipe-src/mediapipe/tasks/c/BUILD
echo "mediapipe source at $commit (version $version, genai dropped)"
