"""Shared constants and helpers for the React Native (Expo) target."""

import shutil;
import subprocess;
import from pathlib { Path }
import from jaclang.cli.console { console }

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
# Defaults mirror REACT_NATIVE_ARCHITECTURE.md decisions D7, D8, D11. Pinned
# versions guard against silent upstream drift breaking the scaffold; bump
# explicitly with a smoke test, not implicitly via "@latest".
glob DEFAULT_PROJECT_DIR_NAME = "mobile-rn",
     DEFAULT_APP_NAME = "main",
     DEFAULT_APP_SLUG = "jac-app",
     DEFAULT_APP_ID = "com.jac.app",
     EXPO_SDK_VERSION = "53",
     REACT_NATIVE_VERSION = "0.76.6",
     SUBPROCESS_TIMEOUT_BUILD: int = 1200;

# Mirrors Capacitor target's install-tool detection. We accept either npm
# or bun. yarn/pnpm not exercised; can be added when a user asks.
def _check_command_available(cmd: list[str], timeout: int = 5) -> bool {
    try {
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout);
        return result.returncode == 0;
    } except Exception {
        return False;
    }
}

"""Resolve npx or bunx for one-off CLI invocations."""
def resolve_npx -> str {
    npx = shutil.which("npx");
    if npx {
        return npx;
    }
    bunx = shutil.which("bunx");
    if bunx {
        return bunx;
    }
    raise RuntimeError(
        "npx or bunx not found. Install Node.js (https://nodejs.org) or "
        "Bun (https://bun.sh) to use --client react-native."
    );
}

"""Install npm packages into the Expo project dir using npm or bun."""
def run_install_cmd(project_dir: Path, packages: list[str], dev: bool = False) {
    if _check_command_available(["npm", "--version"]) {
        cmd = ["npm", "install"];
        if dev {
            cmd.append("--save-dev");
        }
        cmd.extend(packages);
    } elif _check_command_available(["bun", "--version"]) {
        cmd = ["bun", "add"];
        if dev {
            cmd.append("--dev");
        }
        cmd.extend(packages);
    } else {
        raise RuntimeError(
            "Neither npm nor bun is on PATH; install one to scaffold an "
            "Expo project."
        );
    }
    console.print(f"  Installing: {' '.join(packages)}", style="muted");
    subprocess.run(cmd, cwd=project_dir, check=True, capture_output=False);
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
    cfg = _load_rn_dir_config(project_dir);
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

"""Load the raw ``[plugins.client.react_native]`` table for project_dir resolution.

Lighter-weight than ``_load_react_native_config`` in config.jac (which
re-opens ``jac.toml``) — but duplicated here to avoid circular imports
between common.jac and config.jac.
"""
def _load_rn_dir_config(project_dir: Path) -> dict {
    try {
        import tomllib;
        toml_path = project_dir / "jac.toml";
        if toml_path.exists() {
            cfg = tomllib.loads(toml_path.read_text(encoding="utf-8"));
            return cfg.get("plugins", {}).get("client", {}).get("react_native", {});
        }
    } except Exception {
        ;
    }
    return {};
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
