#!/usr/bin/env bash
# Builds the telemetry-free mediapipe wheel locally, inside WSL/Debian — the same
# recipe as CI, minus the runner: no MSVC, no GitHub minutes, and the whole box's
# cores instead of a 4-core runner.
#
# Run it from a copy of this repository that lives on the LINUX filesystem
# (e.g. /root/build/contrib), not from /mnt/…: bazel makes tens of thousands of
# small file operations, and the 9p bridge to the Windows drive makes that
# crawl, inside a filesystem that has room for the build anyway.
#
# Linux only. A Windows wheel needs MSVC (Visual Studio's C++ tools), which
# `mise run setup-system` installs; this script is for the WSL path that needs
# nothing from Windows.
#
#   cp -r /mnt/f/<…>/pware-os-input-vision-contrib /root/build/contrib
#   cd /root/build/contrib && bash scripts/build-local-wsl.sh 2>&1 | tee build.log
set -euo pipefail

# mediapipe builds OpenCV from source, and its CMake probes for these headers.
# The recipe turns the codecs we do not ship (webp, openexr, ffmpeg, gstreamer)
# off, so the -dev packages for those are deliberately absent from this list.
apt-get -qq update
apt-get -qq install -y \
  libjpeg-dev libpng-dev libtiff-dev \
  libavcodec-dev libavformat-dev libavutil-dev libswscale-dev

# The pinned bazel, by hand, exactly as upstream's Dockerfile does it: a
# resolver's opinion is not a pin (on a Windows runner the image's own bazel
# 9.2.0 answered `setup.py` regardless of `.bazelversion`, and from bazel 8 on
# WORKSPACE is off by default — mediapipe's `@flatbuffers` lives there).
if [ "$(bazel --version 2>/dev/null | awk '{print $2}')" != "7.4.1" ]; then
  curl -fL --retry 5 --retry-delay 5 -o /usr/local/bin/bazel \
    https://github.com/bazelbuild/bazel/releases/download/7.4.1/bazel-7.4.1-linux-x86_64
  chmod +x /usr/local/bin/bazel
fi
bazel --version

# Python 3.12 comes from uv (Debian 13 ships 3.13, and mediapipe's setup.py does
# not support it), so the wheel is the same cp312 as the box's environment.
work="$(cd "$(dirname "$0")/.." && pwd)"
python="$work/.venv-build/bin/python"
uv venv "$work/.venv-build" --python 3.12
uv pip install --python "$python" -U setuptools wheel

# Clone the pinned source, stamp the version, apply the anchor-asserting patches.
bash "$work/scripts/checkout.sh"

# Apple-only rules in `MODULE.bazel` (`rules_swift` beside `rules_apple` and
# `apple_support`) abort the analysis of targets that never touch Swift, because
# their autoconfiguration hard-fails where no `swiftc` exists:
#
#   ERROR: Analysis of target '//mediapipe/tasks/metadata:image_segmenter_metadata_schema_py'
#          failed; build aborted: No 'swiftc.exe' executable found in Path
#
# GitHub's ubuntu image happens to ship a Swift toolchain, which is the only
# reason CI's Linux leg passed without this. A Debian box has none, and the
# python wheel path never loads a Swift rule at all — so the module is pointed at
# a stub. (A flag cannot be injected into setup.py's bazel invocation; the
# workspace `.bazelrc` is where flags go.)
cd "$work/mediapipe-src"
mkdir -p swift-stub
printf 'module(name = "rules_swift", version = "2.3.0")\n' > swift-stub/MODULE.bazel
printf 'common --override_module=rules_swift=%s/swift-stub\n' "$PWD" >> .bazelrc

# mediapipe's own .bazelrc asks for `--jobs 1`; bound both jobs and memory
# instead of letting bazel decide (the C++ side of OpenCV is memory-hungry).
{
  printf 'build --jobs=%s\n' "$(( $(nproc) / 2 > 12 ? 12 : $(nproc) / 2 ))"
  printf 'build --local_ram_resources=%s\n' "$(( $(awk '/MemTotal/{print int($2/1024)}' /proc/meminfo) * 3 / 4 ))"
} > ~/.bazelrc

"$python" setup.py bdist_wheel
cd "$work"

# The gate, locally: a wheel carrying Google's uploader must not leave the box.
"$python" scripts/scan-wheel.py --dir mediapipe-src/dist > telemetry-scan-local.json
"$python" - <<'PY'
import json
row = json.load(open("telemetry-scan-local.json"))[0]
print(f"wheel: {row['wheel']} ({row['bytes']} B), clean={row['clean']}")
print(f"markers: {row['counts'][row['libraries'][0]]}")
PY
