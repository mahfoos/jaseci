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

"""Project directory for the Expo scaffold, honoring config overrides."""
def resolve_rn_project_dir(project_dir: Path) -> Path {
    # Phase 1 honors only the default. The full
    # ``[plugins.client.react_native].project_dir`` config knob (D11) lands
    # alongside ``[plugins.client.react_native]`` config loading in a
    # follow-up; keeping resolution centralized here means that change is
    # one-file when it ships.
    return project_dir / DEFAULT_PROJECT_DIR_NAME;
}
