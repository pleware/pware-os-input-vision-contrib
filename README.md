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

The build toolchain (bazel 7.4.1, python 3.12) is provisioned by `ignite` from
the pware-os workspace's `mise.toml` — the single source of truth for the pin.
Platform system deps mise cannot pin live in the per-OS files auto-loaded by
`auto_env` (`mise.windows.toml` → MSVC via winget, `mise.linux.toml` → OpenCV
codecs via apt). After `ignite bootstrap` in `pware-os-workspace`:

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

## How the wheel reaches the box

Open, and deliberately not answered here: publishing to a private repository
needs a credential on the consumer, and a box that promises to make no network
calls should not be fetching a wheel from the internet at install time either.
The umbrella carries the question (`drafts/99`, *how Python reaches the box*).

## Status

The pin, the recipe, the gate and the release job are in place for v1.0.0. The
0.10.35-era recipe never produced a wheel: five `workflow_dispatch` runs on
2026-09-12, all failed, 39–55 minutes each. The first v1.0.0 run is the thing to
watch next; the Windows leg is the one to expect trouble from, because it is the
leg that builds MSVC + bazel + OpenCV from source on a 4-core runner.
