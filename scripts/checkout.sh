#!/usr/bin/env bash
# Clones the pinned mediapipe source commit into ./mediapipe-src and tags the
# build with the pinned version. A raw checkout reports __version__ = 'dev',
# which modern setuptools rejects as an invalid version.
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
echo "mediapipe source at $commit (version $version)"
