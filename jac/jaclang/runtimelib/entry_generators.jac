"""Pluggable client-app entry-script generators.

Core machinery (HMR, eject, the shared client compiler step) needs to write
an `_entry.js` that mounts the compiled `app` export. The exact body of that
script is target-specific: web uses `react-dom/client` + `createRoot`, while
React Native uses `AppRegistry.registerComponent`. Core stays target-neutral
by looking generators up by name; concrete generators ship with the active
jac-client plugin and register themselves at plugin load.

This file deliberately contains no React, DOM, or HTML knowledge.
"""

import from typing { TypeAlias }

# Signature: (entry_module: str, install_global_handlers: bool = True) -> str
glob EntryGenerator: TypeAlias = Callable,
     _generators: dict[str, EntryGenerator] = {};

"""Register `fn` as the entry generator for `target` (e.g. 'web', 'native').

Called at plugin load time from `jac-client`. Re-registering the same target
overrides the previous generator; the last registration wins. This matches
the way the target registry behaves and lets tests swap in stubs.
"""
def register_entry_generator(target: str, fn: EntryGenerator) {
    _generators[target] = fn;
}

"""Look up the entry generator for `target`.

Raises `LookupError` with a clear message if no generator is registered.
We deliberately do not fall back to a default — silent fallbacks would
reintroduce the DOM-in-core coupling that R2 removed.
"""
def get_entry_generator(target: str = "web") -> EntryGenerator {
    fn = _generators.get(target);
    if fn is None {
        raise LookupError(
            f"No entry generator registered for target '{target}'. "
            "Is the jac-client plugin loaded?"
        );
    }
    return fn;
}

"""Whether a generator is registered for `target`."""
def has_entry_generator(target: str) -> bool {
    return target in _generators;
}

"""Drop all registered generators. Test-only — production code should never
call this. Exposed so the test suite can isolate cases."""
def clear_entry_generators {
    _generators.clear();
}
