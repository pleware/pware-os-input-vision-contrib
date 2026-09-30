"""An aspect rules_apple loads by name and appends to `aspects = [...]`."""

def _noop_aspect_impl(target, ctx):
    return []

swift_symbol_graph_aspect = aspect(
    implementation = _noop_aspect_impl,
    attr_aspects = [],
)
