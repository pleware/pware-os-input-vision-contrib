"""One function, loaded by rules_apple's symbol-graph aspects.

It derives a target name from an attribute; nothing calls it on a platform where
the aspects never run.
"""

def derive_swift_module_name(**kwargs):
    return ""
