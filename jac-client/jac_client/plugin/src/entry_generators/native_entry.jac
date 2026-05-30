"""React Native entry-script generator (registry / tests).

Production builds use ``write_native_entry`` in ``react_native/build.jac``,
which emits Expo's ``registerRootComponent(App)`` shell (gesture-handler import,
``app/App.tsx`` wrapper, then ``jac-app.js`` bridge). That is the single mount
path — do not also call ``AppRegistry.registerComponent`` here in the build
flow or the Expo registration will override it.

This module keeps the same ``entry_generators`` contract as the web target
(``entry_module`` + ``install_global_handlers``) for parity and unit tests.
The body registers the compiled module directly via ``AppRegistry`` and is
not written to ``mobile-rn/index.ts``.

The generator self-registers under ``react-native`` (and legacy ``native``)
at import time.
"""

import from jaclang.runtimelib.entry_generators { register_entry_generator }

# Name passed to AppRegistry / Expo. Must match the Expo project's app name —
# the scaffold writes the same constant into ``app.json``'s ``expo.name``
# field, so changing one without the other breaks the registration lookup.
glob NATIVE_ROOT_COMPONENT_NAME = "main";

"""Build a compatibility React Native entry script that registers the compiled Jac
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
    # Compatibility-only code path for runtime registry/tests.
    # ReactNativeTarget.build writes Expo's registerRootComponent entry directly.
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
