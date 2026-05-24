"""Web (React DOM) entry-script generator.

Builds the `_entry.js` that mounts the compiled `app` export under
`JacClientErrorBoundary` via `react-dom/client`'s `createRoot`. Lives in
jac-client because it is target-specific; the contract is the registry in
`jaclang.runtimelib.entry_generators`. This file used to be
`jac/jaclang/runtimelib/react_entry.jac`; moved here in refactor R2.

A Jac client app's bundle is a per-module `<name>.js` that *exports* an
`app` component but never renders it. A separate entry script imports
`app`, wraps it in `JacClientErrorBoundary`, calls `createRoot`, and mounts
at `#root`. That script is generated from at least three places (eject,
HMR, the shared compiler step), so the canonical body lives here — every
coordinated change to the boundary wiring (e.g. adding `onError`) only
touches one location.
"""

import from jaclang.runtimelib.entry_generators { register_entry_generator }

"""Build the entry script that mounts an exported `app` under
`JacClientErrorBoundary`.

Args:
    entry_module: Module basename (no extension) whose `app` export to mount.
    install_global_handlers: Emit `__jacInstallErrorHandlers()`. Pass False
        from HMR re-mounts where the handlers were installed by the initial
        bundle and still bound to `window`.
"""
def build_simple_react_entry_script(
    entry_module: str, install_global_handlers: bool = True
) -> str {
    runtime_imports: list[str] = ['JacClientErrorBoundary', 'ErrorFallback'];
    if install_global_handlers {
        runtime_imports.append('__jacInstallErrorHandlers');
    }
    runtime_imports.append('__jacReactErrorHandler');

    lines: list[str] = [
        'import React from "react";',
        'import { createRoot } from "react-dom/client";',
        f'import {{ app as App }} from "./{entry_module}.js";',
        f'import {{ {", ".join(runtime_imports)} }} from "@jac/runtime";',
        ''
    ];
    if install_global_handlers {
        lines.append('__jacInstallErrorHandlers();');
    }
    lines.extend(
        [
            'const root = createRoot(document.getElementById("root"));',
            'root.render(',
            '\tReact.createElement(',
            '\t\tJacClientErrorBoundary,',
            '\t\t{ FallbackComponent: ErrorFallback, onError: __jacReactErrorHandler },',
            '\t\tReact.createElement(App, null)',
            '\t)',
            ');',
            ''
        ]
    );
    return "\n".join(lines);
}

"""Build the error-overlay entry script HMR writes when a `.cl.jac` file
fails to compile. Renders `errorOverlay(file_path, errors)` at the same
`#root` mount point so the developer sees the failure inline instead of a
stale page.
"""
def build_web_error_overlay_entry_script(file_path: str, errors: str) -> str {
    return (
        'import React from "react";\n'
        'import { createRoot } from "react-dom/client";\n'
        'import { errorOverlay } from "@jac/runtime";\n'
        '\n'
        'const root = createRoot(document.getElementById("root"));\n'
        f'root.render(errorOverlay("{file_path} ", ` {errors}`), null);\n'
    );
}

# Self-register at module load. The plugin's target-registration flow
# imports this module specifically so the side effect runs once per process.
with entry {
    register_entry_generator("web", build_simple_react_entry_script);
    register_entry_generator("web:error_overlay", build_web_error_overlay_entry_script);
}
