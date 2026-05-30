"""React Native entry-script generator.

Builds the JS entry that hands the compiled Jac ``app`` export to
``AppRegistry.registerComponent`` so React Native's runtime can mount it as
the root component (D7: we ship Expo, so the registered name matches the
Expo app config). This is the native analogue of
``web_entry.build_simple_react_entry_script`` — same contract surface
(``entry_module`` + ``install_global_handlers``), different body.

The generator self-registers under the ``react-native`` key in
``jaclang.runtimelib.entry_generators`` at module import time. Importing
``react_native_target.jac`` triggers this import, which guarantees the
generator is wired before any ``jac build --client react-native`` call.

This generator mirrors the Expo root shell used by the native scaffold.
The error-boundary wiring lives in the native runtime, so the entry stays
small and target-specific.
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

# Self-register at module load. Keep ``native`` as a legacy alias for
# compatibility with any downstream code that looked up the old key.
with entry {
    register_entry_generator("react-native", build_native_entry_script);
    register_entry_generator("native", build_native_entry_script);
}
