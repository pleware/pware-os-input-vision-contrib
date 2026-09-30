# pware-os-input-vision-contrib

Telemetry-free wheels for third-party libraries that the vision stack depends
on, built from the upstream source we are allowed to build (Apache-2.0).

## Why

Google's `mediapipe` pip wheels phone home to a `clearcut` telemetry endpoint
with **no off-switch** (google-ai-edge/mediapipe#6291 — Google's own answer:
*"We are not adding an official API to disable this data collection"*, and
*"You can build the SDK from source, which will not include telemetry, or you
can block access to the host"*). The open-source source itself is clean — the
uploader only exists in Google's own build.

Measured here, not read about. Google's wheels, `mediapipe/tasks/c/libmediapipe.dll`:

| Wheel | `clearcut` | `play.googleapis.com` | `ClearcutLoggingClient` | `TasksStatsProtoLogger` |
| --- | --- | --- | --- | --- |
| 0.10.33 (last clean release) | 0 | 0 | 0 | 0 |
| 0.10.35 | 62 | 1 | 3 | 1 |
| 1.0.0 | 66 | 1 | 3 | 1 |
| 1.0.1 | 66 | 1 | 3 | 1 |
| **ours, built from source** | **0** | **0** | **0** | **0** |

The upstream tree at the pinned commit names clearcut **nowhere** (5 4xx paths
scanned, zero matches). A facial-sensor appliance that must not make any network
calls cannot ship Google's wheels, so we build the wheel ourselves.

## What is built

| Library | Upstream | Licence | Output |
| --- | --- | --- | --- |
| mediapipe | google-ai-edge/mediapipe | Apache-2.0 | `mediapipe` wheel, Linux + Windows |

The version we build is **v1.0.0**, and that is the newest *available* source:
PyPI serves a 1.0.1 wheel (2026-08-14) but upstream has never tagged that
source — the newest tag is `v1.0.0` (2026-07-28). A wheel can only be built from
a source release we can name.

## How it works

1. `mediapipe.pin` pins the exact upstream commit we build from.
2. `scripts/checkout.sh` clones that commit, stamps the version, and applies the
   source patches — each one **asserting its anchor still exists** and failing
   loudly when it does not. Three of the 0.10.35-era patches had quietly stopped
   matching by v1.0.0, and a silent `sed` is a lie with a zero exit status.
3. The build runs on Windows (`setup.py bdist_wheel`, runner MSVC) and Linux
   (the same entry point over the system codec headers).
4. `scripts/scan-wheel.py` scans the built wheel and **fails the run** when the
   uploader is present, writing `telemetry-scan.json` beside the artifact. A
   dirty wheel is never published.
5. `release` attaches both wheels, their `SHA256SUMS` and the scan manifest to a
   GitHub release.

v1.0.0 is bzlmod-first (its own `.bazelrc` sets `common --enable_bzlmod`, and it
ships `MODULE.bazel` *and* `WORKSPACE`), so the 0.10.35 recipe's
`--noenable_bzlmod` workaround is gone — that flag was the class of failure
behind all five dead runs of September 2026 (`No repository visible as
'@flatbuffers'`).

The consuming repo (`pware-os-input-vision`) takes the wheel built here, never
Google's PyPI wheel.

## Build locally

The build toolchain (bazel 7.4.1, python 3.12, **a JDK**) is provisioned by
`ignite` from the pware-os workspace's `mise.toml` — the single source of truth
for the pin. The JDK is not a convenience: without one, `rules_java`'s generated
`local_jdk` aborts the analysis of a target that has nothing to do with Java
(`no such package '@@rules_java~//tools/jdk'`), and pointing bazel at a remote JDK
Platform system deps mise cannot pin live in the per-OS files auto-loaded by
`auto_env` (`mise.windows.toml` → MSVC via winget **and Developer Mode**, the
latter because llvm's bazel overlay script symlinks files into its own repository
and Windows hands that privilege to nobody by default — without it the fetch dies
with `WinError 1314 The client does not have the required privilege`, an hour in;
`mise.linux.toml` → OpenCV codecs via apt). After `ignite bootstrap` in
`pware-os-workspace`:

```sh
./build.sh   # setup-system, checkout, build, scan
```

The build is long — mediapipe compiles OpenCV from source — so CI is the usual
path and this script is for proving a recipe change without spending runner
minutes. By hand:

```sh
./scripts/checkout.sh
cd mediapipe-src
python -m pip install --upgrade setuptools wheel
python setup.py bdist_wheel
cd .. && python scripts/scan-wheel.py --dir mediapipe-src/dist
```

### On this box, inside WSL — the faster local path

`scripts/build-local-wsl.sh` needs nothing from Windows and uses the whole
machine (16 cores, ext4) instead of a 4-core runner. Run it from a copy of this
repository on the **Linux** filesystem: bazel makes tens of thousands of small
file operations, and `/mnt/f` is a 9p bridge.

```sh
cp -r /mnt/f/<…>/pware-os-input-vision-contrib /root/build/contrib
cd /root/build/contrib && bash scripts/build-local-wsl.sh 2>&1 | tee build.log
```

It installs everything the build turned out to need, each item because its
absence failed a run — the codec headers OpenCV probes for, a **JDK** (without
one, `rules_java`'s generated `local_jdk` aborts the analysis of a target that has
nothing to do with Java), python 3.12 through `uv` (Debian 13 ships 3.13, which
mediapipe's `setup.py` refuses), and the pinned bazel 7.4.1 as a plain binary.
Measured on this box: **~10 minutes** with a warm bazel cache, the artifact
`mediapipe-1.0.0-cp312-cp312-linux_x86_64.whl` (9.5 MB, scan clean), verified by
installing it in a fresh venv and running a real `FaceLandmarker` inference on
`pware-os-input-vision/vendor/mediapipe/face_landmarker.task`.

The Windows half of that recipe is `./build.sh`, which needs MSVC — `mise run
setup-system` installs it (`scripts/setup-msvc.ps1` in the umbrella, into
`F:\Programy`), plus Developer Mode, which is what lets llvm's bazel overlay
script create the symlinks it needs (`scripts/setup-devmode.ps1`) — stubs the
Apple-only `rules_swift` module, which aborts the analysis on Windows where on
Linux it only warns, and puts the prebuilt OpenCV 3.4.10 where mediapipe looks for
it (`scripts/setup-opencv-windows.ps1`, into `C:\opencv`): on Windows this build
does not compile OpenCV at all — setup.py links the prebuilt libraries through
`@windows_opencv//:opencv` rather than the `opencv_cmake` rule Linux uses.

## How the wheel reaches the box

Open, and deliberately not answered here: publishing to a private repository
needs a credential on the consumer, and a box that promises to make no network
calls should not be fetching a wheel from the internet at install time either.
The umbrella carries the question (`drafts/99`, *how Python reaches the box*).

## Status

The pin, the recipe, the gate and the release job are in place for v1.0.0.

**Linux produces a wheel.** First from CI (two clean runs), and now on the box
itself: `scripts/build-local-wsl.sh` builds it in ~10 minutes and the result was
verified past the scan — installed into a fresh venv, `import mediapipe` → 1.0.0,
and a real `FaceLandmarker` inference on the vision sensor's own
`face_landmarker.task`.

**Windows is one step behind, and the steps are known.** The five dead runs of
2026-09-12 and the first three of 2026-09-30 shared a cause: the runner image's
own bazel (9.2.0, which has WORKSPACE off by default) answered `setup.py`'s bare
`bazel` while the assert step a moment earlier saw 7.4.1 — so `@flatbuffers`,
defined only in mediapipe's WORKSPACE, was invisible. With the pinned binary first
on PATH the build reached mediapipe's own targets and stopped on the Apple-only
`rules_swift`, which aborts analysis where no `swiftc` exists; that module is
stubbed. The run meant to confirm it never started, on GitHub billing — so the
Windows leg is unverified, and the local `./build.sh` (MSVC installed) is now the
cheaper way to verify it than a runner.
