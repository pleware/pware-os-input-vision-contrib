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

```sh
./scripts/checkout.sh
cd mediapipe-src
# requires Bazel; see .github/workflows/build.yml for the exact steps
python setup.py bdist_wheel
```

## Status

Skeleton and pin are in place. The Bazel build itself is being validated —
Linux first, then Windows (MSVC toolchain).
