Telemetry-free mediapipe 1.0.0 wheels, built from the pinned Apache-2.0 source.

## Why these exist

Google's own mediapipe wheels carry a `clearcut` uploader that posts to
`play.googleapis.com`, with no off-switch — Google's answer on
google-ai-edge/mediapipe#6291 is *"We are not adding an official API to disable
this data collection"*. A facial-sensor appliance that must not make network calls
cannot ship them. The open-source source itself is clean; the uploader exists only
in Google's build. So we build it.

Measured on the artifacts attached to this release, against the same markers
Google's wheels carry (`clearcut`, `play.googleapis.com`, `ClearcutLoggingClient`,
`TasksStatsProtoLogger`):

| wheel | clearcut | play.googleapis.com | ClearcutLoggingClient | TasksStatsProtoLogger |
| --- | --- | --- | --- | --- |
| Google's 1.0.1 (for comparison) | 66 | 1 | 3 | 1 |
| **Windows, this release** | 0 | 0 | 0 | 0 |
| **Linux, this release** | 0 | 0 | 0 | 0 |

`SHA256SUMS` and the per-wheel scan manifests (`telemetry-scan-*.json`) are
attached beside them — the scan is a gate in the build, not a report. A wheel that
fails it never leaves the build directory.

## Provenance, in full

Both wheels are **our own builds from the pinned source** (`mediapipe.pin`:
`google-ai-edge/mediapipe`, tag `v1.0.0`, commit `6d31f1eb`), produced locally on
the owner's box while GitHub Actions was stopped on billing. Neither is Google's
artifact, and neither was taken from PyPI.

- **Windows** — `./build.sh` under `mise exec` (MSVC 14.44.35207 and Windows SDK
  10.0.26100 from VS 2022 Build Tools, bazel 7.4.1, python 3.12.10, JDK 21.0.2),
  plain `python setup.py bdist_wheel`. 25 586 237 bytes.
- **Linux** — `scripts/build-local-wsl.sh` in WSL/Debian 13 (16 cores, bazel 7.4.1
  by hand, python 3.12.14 from `uv`, JDK 21), the same entry point. 9 523 042 bytes.

Both wheels come from the **same revision of the recipe** in this repository: the
Linux one was rebuilt after the Windows-only patches landed, so neither predates a
line the other was built with.

The Linux wheel is `linux_x86_64`, not `manylinux`: it installs on the box's Debian
and is not yet a wheel to hand to strangers (`auditwheel repair`, the step
upstream's own `Dockerfile.manylinux_2_28_x86_64` finishes with, is the next move
if that changes).

Both were taken past the scan, each on its own platform:

- **Windows** — installed into a fresh venv, `import mediapipe` → 1.0.0, then a real
  `FaceLandmarker` inference (`running_mode=VIDEO`) against the vision sensor's own
  `vendor/mediapipe/face_landmarker.task`: 1 ms on a 256×256 frame, TensorFlow Lite
  XNNPACK delegate on CPU.
- **Linux** — the same, 1.0.0 and 2 ms.

The Windows wheel carries `mediapipe/tasks/c/opencv_world3410.dll` (55.9 MB
uncompressed) because the OpenCV mediapipe links is a DLL rather than a static
library: the wheel installs on a machine with no OpenCV at all, and `import
mediapipe` works there, which is the only test that settles it.

## The recipe, and what it cost to get here

`scripts/checkout.sh` clones the pinned commit, stamps the version and applies
anchor-asserting source patches; `scripts/scan-wheel.py` is the gate. Patch files
that belong to a fetched module (`patches/*.patch`) travel with the recipe and are
applied through that module's own build system.

Windows is the path upstream never walks in its own CI, and it showed. Every wall
below is now a line in the recipe, with the failure it prevents written beside it:

1. the Apple-only `rules_swift` module aborts analysis where no `swiftc` exists:
   `swift-stub/` is a real package, complete enough to load;
2. no JDK → `rules_java`'s generated `local_jdk` fails in a Java-unrelated target:
   a JDK is part of the toolchain now;
3. a bazel server holds the checkout and `bazel shutdown` returns before it exits:
   the recipe stops the server, deletes the junctions, retries, and fails loudly
   when the tree will not go;
4. llvm's fetch makes symlinks, which Windows refuses without Developer Mode: a
   named prerequisite, probed by the same call llvm makes;
5. Windows links a prebuilt OpenCV from `C:\opencv\build` rather than compiling it:
   the recipe installs it;
6. protobuf refuses MSVC + bazel without `--define=protobuf_allow_msvc=true`;
7. MSVC's traditional preprocessor mishandles mediapipe's status macros:
   `/Zc:preprocessor`, on the host configuration too — `--copt` does not reach it;
8. C11 atomics need `/std:c11` **and** `/experimental:c11atomics` — measured on
   `cl.exe` with a four-line C file: either alone fails, the pair compiles;
9. `api3::SubgraphContext` and `mediapipe::SubgraphContext` collide, and a template
   parameter pack swallows a trailing `DoNotSpecify` parameter;
10. `ABSL_CONST_INIT` on a `thread_local` redefinition (probe-verified on `cl.exe`
    before spending a build cycle);
11. protobuf's MSVC branch drops `@zlib` while its `gzip_stream.h` includes
    `<zlib.h>` regardless — a patch carried in `patches/`;
12. protobuf's JSON parser cannot compile under MSVC at all: `UntypedMessage` holds
    itself inside a `std::variant`, and MSVC checks completeness eagerly (C2139).
    Nothing here reaches protobuf's JSON, so its three translation units are not
    built under MSVC and the linker is the arbiter — Linux still compiles them;
13. the wheel named its library after the bazel label (`libmediapipe.so`) while the
    Python bindings look for `libmediapipe.dll`, and carried no OpenCV runtime:
    both fixed in `patches/mediapipe_windows_wheel_name.patch`, with the build
    refusing to ship a library that cannot be loaded.

The version is **v1.0.0** because that is the newest source upstream has actually
tagged; PyPI serves a 1.0.1 wheel whose source was never released.
