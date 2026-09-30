"""The names the resolved module graph asks of this module, and nothing else.

Nothing here is meant to work; it is meant to *load*. mediapipe's BUILD files
load rules_apple for their iOS targets, and the real rules_apple loads this file
even on a machine that will never build Swift. With no `swiftc` present, the real
rules_swift does not quietly skip — its autoconfiguration aborts the analysis of
targets that have nothing to do with Swift:

    ERROR: .../swift_autoconfiguration.bzl: No 'swiftc.exe' executable found in
    Path. Not auto-generating a Windows Swift toolchain.

So the module is replaced wholesale (--override_module). The names below are not
guessed: they are the union of what the modules in the resolved graph actually
request from this file. `README.md` carries the command that lists them.
"""

# Field lists are generous on purpose: a field is only read by an implementation
# that runs for an Apple target, which is never built here, but an undeclared one
# would be a hard error the day someone does build one.
SwiftInfo = provider(fields = [
    "direct_swift_infos",
    "swift_infos",
    "swiftmodules",
    "transitive_swift_infos",
    "transitive_swiftmodules",
    "swift_interop_info",
    "compilation_context",
    "module_context",
])

SwiftToolchainInfo = provider(fields = [
    "action_configs",
    "cc_toolchain_info",
    "clang_implicit_deps_providers",
    "feature_configuration",
    "internal_toolchain",
    "link_opts",
    "module_interface_opts",
    "object_format",
    "requested_features",
    "supports_dynamic_linking",
    "supports_objc_interop",
    "swift_worker",
    "target",
    "test_configuration",
    "unsupported_features",
])

def _noop_aspect_impl(target, ctx):
    return []

swift_clang_module_aspect = aspect(
    implementation = _noop_aspect_impl,
    attr_aspects = [],
)

def _nothing(*args, **kwargs):
    return None

def _empty_dict(*args, **kwargs):
    return {}

# Macros, not rules: a macro accepts any attribute, so a caller passing something
# unexpected fails nowhere — the target is simply never declared, and nothing in
# the wheel depends on it. A rule would need an attr for every argument.
def swift_library(**kwargs):
    pass

def swift_binary(**kwargs):
    pass

swift_common = struct(
    compile_module_interface = _nothing,
    configure_features = _nothing,
    create_swift_info = _nothing,
    # Returned values become attribute lists and feature lists at load time,
    # so these two answer with the empty container rather than None.
    create_swift_interop_info = _empty_dict,
    toolchain_attrs = _empty_dict,
)
