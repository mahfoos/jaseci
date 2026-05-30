"""Shared constants and helpers for the React Native (Expo) target."""

import subprocess;
import from pathlib { Path }
import from jaclang.cli.console { console }
import from jac_client.plugin.src.targets.build_common {
    SUBPROCESS_TIMEOUT_BUILD_NATIVE
}
import from jac_client.plugin.src.targets.node_tooling_common {
    check_command_available as _node_check_command_available,
    resolve_npx_or_bunx as _node_resolve_npx_or_bunx,
    run_install_cmd as _node_run_install_cmd,
    run_manifest_install as _node_run_manifest_install
}
import from jac_client.plugin.src.targets.react_native.config {
    _load_react_native_config
}

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
# Defaults mirror the documented React Native target decisions in docs/REACT_NATIVE_ARCHITECTURE.md. Pinned
# versions guard against silent upstream drift breaking the scaffold; bump
# explicitly with a smoke test, not implicitly via "@latest".
glob DEFAULT_PROJECT_DIR_NAME = "mobile-rn",
     DEFAULT_APP_NAME = "main",
     DEFAULT_APP_SLUG = "jac-app",
     DEFAULT_APP_ID = "com.jac.app",
     EXPO_SDK_VERSION = "53",
     REACT_NATIVE_VERSION = "0.79.6",
     SUBPROCESS_TIMEOUT_BUILD: int = SUBPROCESS_TIMEOUT_BUILD_NATIVE;

# Mirrors Capacitor target's install-tool detection. We accept either npm
# or bun. yarn/pnpm not exercised; can be added when a user asks.
def _check_command_available(cmd: list[str], timeout: int = 5) -> bool {
    (ok, _) = _node_check_command_available(cmd, timeout=timeout);
    return ok;
}

"""Resolve npx or bunx for one-off CLI invocations."""
def resolve_npx -> str {
    return _node_resolve_npx_or_bunx();
}

"""Install npm packages into the Expo project dir using npm or bun."""
def run_install_cmd(project_dir: Path, packages: list[str], dev: bool = False) {
    _node_run_install_cmd(
        project_dir, packages, dev=dev, default_package_name=DEFAULT_APP_SLUG
    );
}

"""Install all dependencies from the Expo project's package.json."""
def run_manifest_install(project_dir: Path) {
    _node_run_manifest_install(project_dir);
}

"""Run a shell command inside a directory, raising on non-zero exit."""
def run_in_dir(cmd: list[str], cwd: Path, label: str) {
    console.print(f"  Running {label}: {' '.join(cmd)}", style="muted");
    subprocess.run(cmd, cwd=cwd, check=True, capture_output=False);
}

"""Project directory for the Expo scaffold, honoring config overrides (D11).

Reads ``[plugins.client.react_native].project_dir`` from ``jac.toml``.
Falls back to ``mobile-rn/`` when not set.
"""
def resolve_rn_project_dir(project_dir: Path) -> Path {
    cfg = _load_react_native_config(project_dir);
    custom = str(cfg.get("project_dir", "") or "").strip();
    if custom {
        # Treat relative paths as project-root-relative; pass absolute
        # paths through unchanged.
        p = Path(custom);
        if not p.is_absolute() {
            p = project_dir / p;
        }
        return p;
    }
    return project_dir / DEFAULT_PROJECT_DIR_NAME;
}

"""Normalize and validate react-native platform string.

Defaults to ``'android'``. Accepts ``'android'`` or ``'ios'``.
"""
def normalize_rn_platform(platform: str | None = None) -> str {
    if platform is None or platform.strip() == "" {
        return "android";
    }
    value = platform.lower().strip();
    if value in ("android", "ios") {
        return value;
    }
    raise ValueError(
        f"Unsupported react-native platform '{platform}'. " "Supported: android, ios."
    );
}
