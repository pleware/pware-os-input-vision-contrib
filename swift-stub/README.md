# `swift-stub` — the Apple-only Swift module, replaced wholesale

`mediapipe.pin`'s source declares iOS targets in BUILD files that a Linux or
Windows build also loads: `mediapipe/gpu`, `mediapipe/tasks/cc/core` and friends
load `@build_bazel_rules_apple`, and the real `rules_apple` loads
`@build_bazel_rules_swift//swift:swift.bzl` at load time. That load is a *parsing*
dependency, not a build dependency — nothing Swift is ever built for this wheel.

The real `rules_swift` cannot simply be left in place: with no `swiftc` on the
machine its autoconfiguration does not skip quietly, it aborts the analysis of
targets that never touch Swift (`No 'swiftc.exe' executable found in Path. Not
auto-generating a Windows Swift toolchain.`) — files like
`external/rules_swift~/swift/internal/swift_autoconfiguration.bzl` run during the
loading phase. On GitHub's Ubuntu runners a Swift toolchain happens to be
installed, which is why this only bit Windows.

So both build entry points point bazel at this directory:

```sh
printf 'common --override_module=rules_swift=%s/swift-stub\n' \
    "$(cygpath -m "$PWD/mediapipe-src")" >> mediapipe-src/.bazelrc
```

`build.sh` copies it into the checkout first; `.github/workflows/_wheel.yml` does
the same. It is one directory in the repository *on purpose*: the stub used to be
four `printf` lines duplicated in both places, and a stub that must grow cannot
live in two places.

## Adding a name

Do not guess. Ask the graph what it wants — the load statements name both the
file and the symbols:

```sh
grep -rn "@build_bazel_rules_swift" <bazel output base>/external/rules_apple~ |
  grep -o '@build_bazel_rules_swift[^"]*"[^)]*)'
```

A missing *file* fails as `Every .bzl file must have a corresponding package` (add
it with a `BUILD` in its directory); a missing *symbol* fails as
`file 'swift.bzl' does not contain symbol 'X'`. Both errors name the requester.
