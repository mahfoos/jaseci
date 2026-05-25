"""React Native dev loop (Phase 2 — Metro Fast Refresh).

Wires the pieces required to round-trip a ``.cl.jac`` edit to a running
device/emulator in < 3s via Metro's existing Fast Refresh:

    .cl.jac save
        │ JacFileWatcher (watchdog) on the project root
        ▼
    JacClientCompiler.compile(..., runtime_filename="client_runtime_native.cl.jac")
        │ writes refreshed JS into .jac/client/compiled/
        ▼
    stage_compiled_entry(...)  →  mobile-rn/jac-app.js
        │ Metro picks up the file change via watchFolders (set by scaffold)
        ▼
    Metro Fast Refresh
        │ ships the new module to the device
        ▼
    Native runtime swaps the module without losing state

The Vite/Capacitor dev story (``targets/mobile/dev.jac``) inspired the
shape of this module, but the implementation diverges because Metro owns
its own watcher + transformer pipeline. We do *not* run ``expo start`` as
a subprocess from inside an HMR loop; instead we ``exec`` the Metro
process and put the .jac → JS recompile + adb-reverse + API base-URL
plumbing around it.

Module layout intentionally mirrors ``mobile/dev.jac`` so reviewers
familiar with one can navigate the other; the duplication of small
helpers (port assertion, watchdog probe, backend launcher) is deliberate
— extracting a ``client_dev_common.jac`` deserves its own session against
the green Capacitor suite.
"""

import json;
import os;
import shutil;
import socket;
import subprocess;
import from pathlib { Path }
import from typing { Any, Optional, cast }
import from jaclang.cli.console { console }
import from jaclang.runtimelib.watcher { FileChangeEvent }
import from jac_client.plugin.src.targets.react_native.common {
    resolve_npx,
    resolve_rn_project_dir
}
import from jac_client.plugin.src.targets.react_native.build {
    lint_native_incompatible_usage,
    lint_unmapped_tags,
    stage_native_image_assets,
    stage_compiled_entry,
    write_native_entry
}
# Re-use the JacRuntime hub eviction helper from the Capacitor target —
# the underlying invariant (stale module cache survives between compiles)
# is identical, and forking it would mean two places to fix bugs in.
import from jac_client.plugin.src.targets.mobile.dev {
    _mobile_invalidate_runtime_module_cache
}

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------
# Metro defaults to 8081; respect a JAC_RN_METRO_PORT override so two
# concurrent dev loops (rare but exercised in CI) can avoid each other.
glob JAC_RN_METRO_PORT_ENV: str = "JAC_RN_METRO_PORT",
     JAC_RN_DEV_HOST_ENV: str = "JAC_RN_DEV_HOST",
     DEFAULT_METRO_PORT: int = 8081,
     SUBPROCESS_TIMEOUT_SHORT: int = 5;

# ---------------------------------------------------------------------------
# Port + host resolution
# ---------------------------------------------------------------------------
"""Resolve Metro port: env override > cli value > 8081."""
def resolve_metro_port(cli_port: int = DEFAULT_METRO_PORT) -> int {
    raw = os.environ.get(JAC_RN_METRO_PORT_ENV, "");
    if raw and str(raw).strip() {
        try {
            return int(str(raw).strip());
        } except Exception {
            return cli_port;
        }
    }
    return cli_port;
}

"""Fail fast if a port is already bound.

Mirrors the Capacitor-dev port assertion. The API subprocess silently
bumps the port on EADDRINUSE which would leave the adb-reverse mapping
and the build-time ``__JAC_API_BASE_URL__`` pointing at a dead port —
explicit failure here is the only way to make that mode visible.
"""
def assert_rn_port_available(port: int, role: str) {
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM);
    try {
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1);
        s.bind(("0.0.0.0", port));
    } except OSError as e {
        raise RuntimeError(
            f"{role} port {port} is already in use ({e}). The react-native "
            "dev loop needs deterministic ports so adb reverse and the "
            "API base-URL injected into app.json match what's actually "
            "listening. Stop the conflicting process or pass a different "
            f"port (e.g. --port {port + 100})."
        );
    } finally {
        s.close();
    }
}

# ---------------------------------------------------------------------------
# adb reverse (Android dev connectivity)
# ---------------------------------------------------------------------------
"""Best-effort `adb reverse` so the device can reach Metro + the Jac API
over localhost. No-op when adb isn't on PATH (no device anyway). The
Metro CLI itself runs ``adb reverse tcp:8081`` on startup, but doing it
here too means our API port also gets reversed — Metro only handles its
own port, not the Jac API the device will call.
"""
def setup_android_port_reverse(metro_port: int, api_port: int) -> None {
    if not shutil.which("adb") {
        return;
    }
    def _try(port: int) {
        cmd = ["adb", "reverse", f"tcp:{port}", f"tcp:{port}"];
        try {
            r = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=SUBPROCESS_TIMEOUT_SHORT,
                check=False
            );
            if r.returncode == 0 {
                console.print(
                    f"  ✔ adb reverse tcp:{port} tcp:{port}", style="success"
                );
            } else {
                err = (r.stderr or "").strip() or "unknown adb error";
                console.warning(f"  ⚠ adb reverse failed for tcp:{port} ({err})");
            }
        } except Exception as e {
            console.warning(f"  ⚠ adb reverse failed for tcp:{port} ({e})");
        }
    }
    _try(metro_port);
    if api_port != metro_port {
        _try(api_port);
    }
}

# ---------------------------------------------------------------------------
# app.json api base URL injection
# ---------------------------------------------------------------------------
"""Rewrite ``mobile-rn/app.json``'s ``expo.extra.apiBaseUrl`` to the dev
URL and return the original raw text so it can be restored on exit.

Why app.json instead of a build-time global: ``__getApiBaseUrl`` already
reads ``Constants.expoConfig.extra.apiBaseUrl`` as the second-tier
fallback. Editing app.json means the change is picked up by the *next*
Metro module load (the user's first navigation will see it) without us
having to regenerate index.ts or invent a new injection mechanism. The
trade-off — needing to restore on exit — is well-contained: we write the
original back in a ``finally`` block. If a crash leaves the file munged,
``jac setup react-native`` regenerates it from the scaffold.
"""
def inject_dev_api_base_url(rn_dir: Path, api_url: str) -> Optional[str] {
    config_path = rn_dir / "app.json";
    if not config_path.exists() {
        console.warning(
            f"  app.json not found at {config_path}; skipping API URL injection. "
            "Run `jac setup react-native` to regenerate the scaffold."
        );
        return None;
    }
    original = config_path.read_text(encoding="utf-8");
    try {
        cfg = json.loads(original);
    } except Exception as e {
        console.warning(f"  Could not parse app.json ({e}); skipping injection.");
        return None;
    }
    expo = cfg.get("expo", {});
    extra = expo.get("extra", {});
    extra["apiBaseUrl"] = api_url;
    expo["extra"] = extra;
    cfg["expo"] = expo;
    config_path.write_text(json.dumps(cfg, indent=2) + "\n", encoding="utf-8");
    console.print(f"  ✔ app.json → expo.extra.apiBaseUrl = {api_url}", style="success");
    return original;
}

"""Restore ``mobile-rn/app.json`` to its pre-dev state. No-op if injection
returned None (file missing / unparseable) so failed injection doesn't
leave us writing garbage on shutdown.
"""
def restore_app_json(rn_dir: Path, original: Optional[str]) -> None {
    if original is None {
        return;
    }
    config_path = rn_dir / "app.json";
    try {
        config_path.write_text(original, encoding="utf-8");
        console.print("  ✔ Restored app.json", style="muted");
    } except Exception as e {
        console.warning(f"  Failed to restore app.json: {e}");
    }
}

# ---------------------------------------------------------------------------
# Backend (jaclang start) subprocess
# ---------------------------------------------------------------------------
"""Spawn the Jac API server as a subprocess. Same shape as
``mobile/dev._mobile_start_backend_server`` — duplicated here so the
react-native dev path doesn't reach into the Capacitor target's
internals for what is fundamentally a generic ``jac start --no_client``
invocation.
"""
def start_backend_server(entry_file: Path, project_dir: Path, port: int) -> any {
    import sys;
    return subprocess.Popen(
        [
            sys.executable,
            "-m",
            "jaclang",
            "start",
            str(entry_file),
            "--port",
            str(port),
            "--no_client"
        ],
        cwd=str(project_dir),
        stdout=None,
        stderr=None
    );
}

# ---------------------------------------------------------------------------
# Watchdog probe + HMR callback
# ---------------------------------------------------------------------------
"""Return True if watchdog is importable. Mirrors the Capacitor guard so
users get the same actionable message regardless of which target they
run.
"""
def ensure_watchdog -> bool {
    try {
        import watchdog;
        return True;
    } except ImportError {
        console.warning(
            "  watchdog not installed — saving .jac files will not refresh the device. "
            "Install with: pip install 'watchdog>=3.0.0' (or add to [dev-dependencies]).",
            style="muted"
        );
        return False;
    }
}

"""Recompile the Jac client graph after a save and re-stage the entry
into ``mobile-rn/`` so Metro Fast Refresh picks it up.

Runs on the watchdog thread; any exception is swallowed (with a console
log) because killing the watcher on a transient compile error would
require the user to restart ``jac start`` for every typo.

The lint pass is intentionally outside the try/except so unmapped-tag
warnings still surface on save. Metro is happy regardless — the lint is
purely advisory at this layer.
"""
def rn_hmr_on_jac_changed(
    event: FileChangeEvent,
    compiler: any,
    entry_file: Path,
    project_dir: Path,
    rn_dir: Path,
    entry_module: str
) -> None {
    try {
        pth = event.path or "";
        if not pth or not pth.endswith(".jac") {
            return;
        }
        try {
            Path(pth).resolve().relative_to(project_dir.resolve());
        } except ValueError {
            return;
        }
        _mobile_invalidate_runtime_module_cache([pth, str(entry_file)]);
        compile_out = cast(Any, compiler.jac_compiler.compile_module(entry_file));
        mod2 = compile_out[1];
        if not mod2 {
            return;
        }
        compiler.compile(
            mod2,
            entry_file,
            runtime_filename="client_runtime_native.cl.jac",
            target_name="react-native"
        );
        compiled_dir = compiler.compiled_dir;
        if compiled_dir is not None {
            try {
                stage_native_image_assets(compiled_dir, rn_dir);
            } except Exception as asset_err {
                console.warning(f"  HMR asset stage warning: {asset_err}");
            }
            try {
                stage_compiled_entry(compiled_dir, rn_dir, entry_module);
            } except Exception as stage_err {
                console.error(f"  HMR stage failed: {stage_err}");
                return;
            }
            try {
                lint_unmapped_tags(compiled_dir);
            } except Exception { }
            try {
                lint_native_incompatible_usage(compiled_dir);
            } except Exception { }
        }
        try {
            console.print(
                "  ✔ Native client recompiled — Metro will Fast Refresh",
                style="success"
            );
        } except Exception { }
    } except Exception as e {
        try {
            console.error(f"  HMR recompile failed: {e}");
        } except Exception { }
    }
}

# ---------------------------------------------------------------------------
# Metro / Expo CLI invocation
# ---------------------------------------------------------------------------
"""Build the ``expo start`` argv used by the dev loop. Pure for testability.

`--port` pins Metro to the resolved port (matches what we adb-reversed).
`--clear` empties Metro's transform cache; we pass it on every dev start
because the Jac compile output filenames are stable but the contents
change per-edit, and Metro's cache key is filename-only.
"""
def build_expo_start_argv(metro_port: int, clear_cache: bool = True) -> list[str] {
    argv: list[str] = [resolve_npx(), "expo", "start", "--port", str(metro_port)];
    if clear_cache {
        argv.append("--clear");
    }
    return argv;
}

"""Run ``npx expo start`` blocking until the user presses Ctrl+C.

We intentionally do *not* capture stdout — the Metro UI (QR code, key
shortcuts, live logs) is the user-facing surface during dev, and stealing
its TTY would be a major regression vs. running ``expo start`` directly.
"""
def run_expo_start(rn_dir: Path, metro_port: int, clear_cache: bool = True) -> int {
    argv = build_expo_start_argv(metro_port, clear_cache=clear_cache);
    console.print(f"  Running: {' '.join(argv)}", style="muted");
    console.print("  (Press Ctrl+C to stop)\n", style="muted");
    result = subprocess.run(argv, cwd=str(rn_dir), check=False);
    return result.returncode;
}
