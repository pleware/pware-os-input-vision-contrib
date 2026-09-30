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
#    distros (OpenEXR 2.x, FFmpeg avresample, GStreamer), and OpenCV's own
#    command-line tools — the latter because linking them is a toolchain trap,
#    not because we would mind their size.
# 2. Drop the same libs from the static `linkopts` list — that hardcoded list is
#    what actually breaks the link on a modern system, independent of #1.
# 3. Normalize CRLF: mediapipe's own `.bazelrc` lines are read by bazel before
#    anything of ours runs, and a CRLF checkout on Windows breaks them.
# 4. Pin the python the build resolves against (`default_python_version`), so the
#    wheel does not depend on which python3 the host distro ships.
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

# A bazel server keeps the checkout alive, and on Windows one open handle is
# enough to make a recursive delete fail — and `bazel shutdown` returns before the
# server has actually exited. Deleting the checkout is the first thing this script
# does, so a failure here costs a whole build to discover (it surfaces as
# `rm: cannot remove 'mediapipe-src': Device or resource busy`, one line into a log
# nobody reads until the build is over). Three Windows facts, measured the hard way:
#
# 1. a live server holds handles into the tree;
# 2. bazel's convenience symlinks in the workspace root (`bazel-bin`, `bazel-out`,
#    …) are junctions, and MSYS `rm -rf` refuses a directory holding one —
#    reporting "busy" for the whole tree, which is why the same tree deleted fine
#    from PowerShell and never from this shell;
# 3. a delete that fails silently leaves the previous checkout in place.
#
# So: stop the server, undo the junctions with the tool that owns them (plain
# `rmdir` removes the link, never its target — the target is the bazel output base,
# which the next build wants to keep), then delete with retries, and exit 1 naming
# the cause if the directory survives.
if [ -d mediapipe-src ]; then
  (cd mediapipe-src && bazel shutdown >/dev/null 2>&1) || true
  for link in mediapipe-src/bazel-*; do
    [ -e "$link" ] || [ -L "$link" ] || continue
    cmd //c rmdir "$(cygpath -w "$link")" >/dev/null 2>&1 || true
  done
  for _ in 1 2 3 4 5 6; do
    if rm -rf mediapipe-src 2>/dev/null; then break; fi
    sleep 5
  done
  [ ! -d mediapipe-src ] || {
    echo "checkout: cannot remove mediapipe-src — a process still holds it" >&2
    exit 1
  }
fi
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

# 1. Disable OpenCV codecs that are gone/renamed on modern distros (OpenEXR 2.x,
#    FFmpeg avresample, GStreamer) and OpenCV's own tools.
#
#    `BUILD_opencv_apps` is not about size: OpenCV builds the executables in its
#    `apps/` directory (opencv_annotation and friends), and linking those is what
#    fails on a modern toolchain, because the foreign_cc crosstool links C++ with
#    `gcc` rather than `g++` and the link line then carries no libstdc++:
#
#      /usr/bin/ld: ../../lib/libopencv_imgcodecs.a(loadsave.cpp.o): undefined
#        reference to symbol '_ZNSt15basic_streambufIcSt11char_traitsIcEE8overflowEi@@GLIBCXX_3.4'
#      make[2]: *** [.../apps/annotation/CMakeFiles/opencv_annotation.dir/build.make:109:
#        bin/opencv_annotation] Error 1
#
#    We want the static libraries and not one byte of the tools. Turning them off
#    removes the failure instead of papering over the link line.
apply mediapipe-src/third_party/BUILD '"WITH_WEBP": "OFF",' \
  's/"WITH_WEBP": "OFF",/"WITH_WEBP": "OFF",\n        "WITH_OPENEXR": "OFF",\n        "WITH_FFMPEG": "OFF",\n        "WITH_GSTREAMER": "OFF",\n        "BUILD_opencv_apps": "OFF",/'

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

# 4. Pin the python the build resolves against. `default_python_version =
#    "system"` means "whatever python3 the host happens to ship", and the four
#    lock files stop at 3.12: on GitHub's ubuntu image the host python3 is 3.12
#    (so it worked), on Debian 13 it is 3.13 and the build dies before it starts
#    with `Error computing the main repository mapping: no such package
#    '@@python_version_repo//': Could not find requirements_lock.txt file
#    matching specified Python version`. The wheel is cp312 in every case —
#    nothing here wants the host's version, so it stops being asked for it.
apply mediapipe-src/WORKSPACE 'default_python_version = "system",' \
  's/default_python_version = "system",/default_python_version = "3.12",/'

# 5. protobuf at this pin refuses to compile under MSVC unless the build says it
#    accepts the risk, in as many words:
#
#      external/protobuf~/src/google/protobuf/stubs/port.h(38): fatal error C1189:
#      #error: "Protobuf will be dropping support for MSVC + Bazel in 34.0. To
#      continue using it until then, use the flag --define=protobuf_allow_msvc=true."
#
#    It goes in .bazelrc rather than in the build command because the command is
#    built by setup.py, and every caller would have to remember it; and it is not
#    conditioned on the platform because it is inert on one — the guard lives behind
#    `#if defined(_MSC_VER)`, so Linux compiles the same source either way.
if ! grep -q 'protobuf_allow_msvc' mediapipe-src/.bazelrc; then
  printf 'build --define=protobuf_allow_msvc=true\n' >> mediapipe-src/.bazelrc
fi

# 6. MSVC's *traditional* preprocessor cannot expand mediapipe's variadic dispatch
#    macros. `MP_ASSIGN_OR_RETURN(auto hwc, ...)` in ordinary code then fails like
#    this, three errors deep, in a file that has nothing to do with macros:
#
#      tensors_to_segmentation_calculator.cc(175): error C2144: syntax error:
#        "auto" should be preceded by ";"
#      (204): error C2065: "MP_STATUS_MACROS_IMPL_REM": undeclared identifier
#
#    `/Zc:preprocessor` switches MSVC to the conforming one (VS2019 16.5+). It goes
#    in the `windows` config, which the upstream .bazelrc already activates by
#    itself through `--enable_platform_specific_config` — so it costs a Linux build
#    nothing and needs no platform test here.
if ! grep -q '/Zc:preprocessor' mediapipe-src/.bazelrc; then
  printf 'build:windows --copt=/Zc:preprocessor\n' >> mediapipe-src/.bazelrc
fi

# 7. MSVC compiles C its own historical way unless told otherwise, and C11 atomics
#    are not part of it. pthreadpool is a C library and uses them:
#
#      external/pthreadpool/BUILD.bazel: Compiling src/portable-api.c failed:
#      vcruntime_c11_stdatomic.h(16): fatal error C1189:
#      #error: "C atomics require C11 or later"
#
#    `--conlyopt` is bazel's knob for C alone, which is what this needs: the C++
#    side already has /std:c++20 from the same config, and handing `/std:c11` to a
#    C++ compile is an error in itself. Nothing here sets a C standard for any
#    platform -- GCC simply defaults to gnu11/gnu17, so only MSVC ever needed it.
if ! grep -q '/std:c11' mediapipe-src/.bazelrc; then
  printf 'build:windows --conlyopt=/std:c11\n' >> mediapipe-src/.bazelrc
fi

# 8. Two classes named SubgraphContext in different namespaces: mediapipe's
#    framework/subgraph.h has a plain one, api3/subgraph_context.h a template. graph.h
#    declares the api3 template a friend without including its header, so unqualified
#    lookup finds the outer plain class first and MSVC refuses the declaration:
#
#      mediapipe/framework/api3/graph.h(324): error C3857:
#      "mediapipe::SubgraphContext": multiple template parameter lists are not allowed
#
#    GCC and clang read it as introducing the template in this scope and compile.
#    A forward declaration of the template, in the namespace it belongs to, removes
#    the ambiguity for every compiler.
apply mediapipe-src/mediapipe/framework/api3/graph.h \
  'namespace mediapipe::api3 {' \
  's|namespace mediapipe::api3 {|namespace mediapipe::api3 {\n\n// Declared here to disambiguate the friend declaration below: the plain\n// mediapipe::SubgraphContext in framework/subgraph.h and this template share a\n// name, and without this line MSVC resolves the friend to the plain class.\ntemplate <typename NodeT>\nclass SubgraphContext;|'

# 9. MSVC will not accept a template parameter that follows a parameter pack and
#    cannot be deduced, and the api3 free functions order theirs that way:
#
#      mediapipe/framework/api3/calculator_context.h(436): error C3547: cannot use
#      template parameter "DoNotSpecify" because it follows a template parameter
#      pack and cannot be deduced from the parameters of function
#      "mediapipe::api3::internal::VisitPacketOrDie"
#
#    `int&... DoNotSpecify` is a guard whose entire job is to stop the next
#    parameter (`F`) from being given explicitly. All four call sites in the tree
#    pass types only -- `<U, Rest...>`, `<PayloadTs...>` -- so the guard has nothing
#    to guard in this build. Removing it is the fix; relying on a compiler
#    difference would be the workaround.
apply mediapipe-src/mediapipe/framework/api3/calculator_context.h \
  ', int&... DoNotSpecify,' \
  's/, int&\.\.\. DoNotSpecify,/,/g'

echo "mediapipe source at $commit (version $version, patched)"
