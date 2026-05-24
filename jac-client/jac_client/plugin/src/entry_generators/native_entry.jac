"""React Native entry-script generator.

Builds the JS entry that hands the compiled Jac ``app`` export to
``AppRegistry.registerComponent`` so React Native's runtime can mount it as
the root component (D7: we ship Expo, so the registered name matches the
Expo app config). This is the native analogue of
``web_entry.build_simple_react_entry_script`` — same contract surface
(``entry_module`` + ``install_global_handlers``), different body.

The generator self-registers under the ``native`` key in
``jaclang.runtimelib.entry_generators`` at module import time. Importing
``react_native_target.jac`` triggers this import, which guarantees the
generator is wired before any ``jac build --client react-native`` call.

This is a Phase 1 skeleton: the body matches what the Phase 0 spike's
``index.ts`` does today, minus error-boundary wiring (we'll add an RN
``ErrorBoundary`` adapter alongside the native runtime split — D9).
"""

import from jaclang.runtimelib.entry_generators { register_entry_generator }

# Name passed to AppRegistry / Expo. Must match the Expo project's app name —
# the scaffold writes the same constant into ``app.json``'s ``expo.name``
# field, so changing one without the other breaks the registration lookup.
glob NATIVE_ROOT_COMPONENT_NAME = "main";

"""Build the React Native entry script that registers the compiled Jac
``app`` export as the Expo root component.

Args:
    entry_module: Module basename (no extension) whose ``app`` export to
        register. Matches the basename of the compiled JS module in
        ``.jac/client/compiled/``.
    install_global_handlers: Reserved for parity with the web generator.
        On RN, global error handling is set up via ``ErrorUtils`` /
        ``LogBox`` rather than ``window.onerror``; the native runtime
        installs them at module load, so this flag is currently inert and
        kept only so the registry contract is the same shape across
        targets.
"""
def build_native_entry_script(
    entry_module: str, install_global_handlers: bool = True
) -> str {
    lines: list[str] = [
        'import { AppRegistry } from "react-native";',
        f'import {{ app as JacApp }} from "./{entry_module}.js";',
        '',
        f'AppRegistry.registerComponent({NATIVE_ROOT_COMPONENT_NAME!r}, () => JacApp);',
        ''
    ];
    return "\n".join(lines);
}

# Self-register at module load. The target-registration flow imports this
# module specifically (via `react_native_target.jac`) so the side effect
# runs once per process — same pattern as `web_entry.jac`.
with entry {
    register_entry_generator("native", build_native_entry_script);
}
