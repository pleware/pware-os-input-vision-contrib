# pware-os-input-vision-contrib

Telemetry-free wheels for third-party libraries that the vision stack depends
on, built from the upstream source we are allowed to fork (Apache-2.0).

## Why

Google's `mediapipe` pip wheels phone home to a `clearcut` telemetry endpoint
with **no off-switch** (google-ai-edge/mediapipe#6291). The open-source source
itself is clean — the tracker is injected only into Google's own build. A
facial-sensor appliance that must not make any network calls cannot ship those
wheels, so we build the wheel ourselves from the pinned source.

## What is built

| Library | Upstream | Licence | Output |
| --- | --- | --- | --- |
| mediapipe | google-ai-edge/mediapipe | Apache-2.0 | `mediapipe` wheel, Linux + Windows |

## How it works

1. `mediapipe.pin` pins the exact upstream commit we build from.
2. `scripts/checkout.sh` clones that commit.
3. GitHub Actions (`build.yml`) builds the wheel on Linux and Windows and
   releases both as artifacts.

The consuming repo (`pware-os-input-vision`) depends on the wheel built here,
never on Google's PyPI wheel.

## Build locally

The build toolchain (bazel 7.4.1, python 3.12) is provisioned by `ignite` from
the pware-os workspace's `mise.toml` — the single source of truth for the pin.
Platform system deps mise cannot pin live in the per-OS files auto-loaded by
`auto_env` (`mise.windows.toml` → MSVC via winget, `mise.linux.toml` → OpenCV
codecs via apt). After `ignite bootstrap` in `pware-os-workspace`:

```sh
./build.sh   # runs `mise run setup-system` first, then builds the wheel
```

Or by hand:

```sh
./scripts/checkout.sh
cd mediapipe-src
python -m pip install --upgrade setuptools wheel
python setup.py bdist_wheel
```

## Status

Skeleton, pin, and the ignite-provisioned toolchain are in place, with
per-OS system deps handled by the `setup-system` task. The Bazel build itself
is being validated — Linux first, then Windows.
