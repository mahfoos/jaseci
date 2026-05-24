"""Implementation of ReactNativeTarget lifecycle methods (Phase 1).

`setup`  — scaffolds the Expo project under ``mobile-rn/`` and installs
            native deps (idempotent; safe to re-run).
`build`  — JacClientCompiler(native runtime) -> stage compiled JS into
            mobile-rn/ -> expo prebuild -> gradlew assembleDebug.
            Returns the path to the produced APK.
`dev`    — Phase 2 (Fast Refresh). Still NotImplementedError today; the
            scaffolding to add it is in place (the runtime is registered,
            metro.config.js watches the compiled dir).
`start`  — Wraps ``build`` + ``adb install`` + ``adb shell am start`` to
            launch on the connected device/emulator. iOS deferred to
            Phase 4.

The intentional NotImplementedError for ``dev`` is part of the user
contract: running ``jac start --client react-native --dev`` today reports
exactly what is unfinished and points at the roadmap, rather than
silently doing the wrong thing.
"""

import os;
import shutil;
import subprocess;
import from typing { cast }
import from jaclang.cli.console { console }
import from jaclang.runtimelib.watcher { FileChangeEvent }
import from jac_client.plugin.src.targets.react_native.common {
    DEFAULT_APP_ID,
    DEFAULT_APP_NAME,
    DEFAULT_APP_SLUG,
    resolve_rn_project_dir
}
import from jac_client.plugin.src.targets.react_native.scaffold {
    ensure_native_deps_installed,
    write_expo_scaffold
}
import from jac_client.plugin.src.targets.react_native.build {
    lint_unmapped_tags,
    run_expo_prebuild,
    run_gradle_assemble_debug,
    stage_compiled_entry,
    write_native_entry
}
import from jac_client.plugin.src.targets.react_native.dev {
    SUBPROCESS_TIMEOUT_SHORT as DEV_SUBPROCESS_TIMEOUT_SHORT,
    assert_rn_port_available,
    ensure_watchdog as ensure_dev_watchdog,
    inject_dev_api_base_url,
    resolve_metro_port,
    restore_app_json,
    rn_hmr_on_jac_changed,
    run_expo_start,
    setup_android_port_reverse,
    start_backend_server,
    JAC_RN_DEV_HOST_ENV
}
import from jac_client.plugin.src.mobile_dev_host { detect_lan_ipv4 }

glob _ROADMAP_URL = "REACT_NATIVE_ARCHITECTURE.md";

"""Setup the Expo project scaffold and install native deps.

Idempotent: re-running picks up changes to the scaffold templates but
leaves user-edited files (``app/App.tsx``, ``app.json``) alone — see
``_is_scaffold_managed`` in scaffold.jac for the marker-based detection.
"""
impl ReactNativeTarget.setup(project_dir: Path) -> None {
    rn_dir = resolve_rn_project_dir(project_dir);
    console.print(
        f"\n📱 Setting up React Native target (Expo) at {rn_dir}", style="bold"
    );

    wrote_new = write_expo_scaffold(
        rn_dir,
        project_dir,
        app_name=DEFAULT_APP_NAME,
        app_slug=DEFAULT_APP_SLUG,
        app_id=DEFAULT_APP_ID
    );

    if wrote_new {
        try {
            ensure_native_deps_installed(rn_dir);
        } except Exception as e {
            console.warning(
                f"  npm install failed: {e}\n"
                "  Run `npm install` (or `bun install`) inside "
                f"{rn_dir} manually before running `jac build`."
            );
        }
    } else {
        console.print(
            "  ✔ Scaffold already current; skipping npm install", style="muted"
        );
    }

    console.success("React Native target setup complete.");
    console.print("\nNext steps:", style="bold");
    console.print(
        "  Build: jac build --client react-native --platform android", style="muted"
    );
    console.print(
        "  Dev:   jac start --client react-native --dev " "(Phase 2 — not yet)",
        style="muted"
    );
}

"""Build a debug APK from the compiled Jac bundle.

Platform must be 'android' for Phase 1. iOS is deferred to Phase 4 — we
fail loudly here so users don't get a partial result they then try to
ship.
"""
impl ReactNativeTarget.build(
    entry_file: Path, project_dir: Path, platform: Optional[str] = None
) -> Path {
    import from jac_client.plugin.src.jac_client_compiler { JacClientCompiler }
    import from jac_client.plugin.client { JacClient }

    plat = (platform or "android").lower();
    if plat == "ios" {
        raise NotImplementedError(
            "iOS builds for --client react-native are a Phase 4 feature. "
            f"See {_ROADMAP_URL} (Phase 4). For Phase 1 use --platform android."
        );
    }
    if plat != "android" {
        raise ValueError(
            f"Unsupported platform '{plat}' for --client react-native. "
            "Use --platform android (iOS lands in Phase 4)."
        );
    }

    console.print(
        "\n📱 Building React Native app (Expo + Metro + Gradle)", style="bold"
    );

    rn_dir = resolve_rn_project_dir(project_dir);
    if not (rn_dir / "package.json").exists() {
        console.print("  Scaffold not found — running setup first...", style="muted");
        self.setup(project_dir);
    }

    # Step 1: compile Jac modules + the *native* runtime. We reach through
    # to the inner ``JacClientCompiler`` (bypassing ViteCompiler's web-only
    # ``create_entry_file``) — ViteCompiler is a thin orchestrator and its
    # ``compile`` would write a DOM-shaped _entry.js we don't want.
    console.print("  Step 1: Compiling Jac modules + native runtime...", style="muted");
    builder = JacClient.get_client_bundle_builder();
    # Some builders (the simple one) don't have a Vite package.json wired,
    # but JacClient.get_client_bundle_builder returns the Vite variant
    # which sets up `vite_package_json` lazily from project config.
    vite_compiler = builder._get_compiler();
    jac_compiler = vite_compiler.jac_client_compiler;
    compiled_dir = jac_compiler.compiled_dir;
    if compiled_dir is None {
        raise RuntimeError(
            "JacClientCompiler.compiled_dir is None; project config likely "
            "missing. Run `jac setup react-native` first."
        );
    }
    compiled_dir.mkdir(parents=True, exist_ok=True);
    (_, mod, _) = jac_compiler.jac_compiler.compile_module(entry_file);
    if not mod {
        raise RuntimeError(f"Failed to compile client entry module: {entry_file}");
    }
    jac_compiler.compile(
        mod, entry_file, runtime_filename="client_runtime_native.cl.jac"
    );
    console.print("  ✔ Jac modules compiled with native runtime", style="success");

    # Step 1b: lint pass — surface unmapped HTML tags before Metro burns
    # cycles bundling something the renderer will fall back on.
    lint_unmapped_tags(compiled_dir);

    # Step 2: stage compiled entry + write index.ts so Metro picks them up.
    entry_module: str = entry_file.stem;
    stage_compiled_entry(compiled_dir, rn_dir, entry_module);
    write_native_entry(rn_dir, "jac-app");

    # Step 3: expo prebuild — generates android/ from app.json + plugins.
    console.print("  Step 2: Running expo prebuild (Android)...", style="muted");
    run_expo_prebuild(rn_dir);

    # Step 4: gradle assembleDebug — produces the APK.
    console.print("  Step 3: Building Android APK with Gradle...", style="muted");
    apk_path = run_gradle_assemble_debug(rn_dir);

    console.success(f"React Native build complete: {apk_path}");
    console.print("\nInstall with: adb install -r " + str(apk_path), style="muted");
    return apk_path;
}

"""Start the Metro dev loop with Fast Refresh — Phase 2.

Orchestration (Android-only for v1; iOS sim is best-effort once Metro is
up because Expo's CLI handles both, but our adb-reverse + emulator-host
defaults assume Android):

    1. Resolve dev host (env override > LAN IPv4 > 127.0.0.1).
    2. Pick Metro port + API port; assert both free *before* mutating
       any config (otherwise we'd leave app.json / adb-reverse pointing
       at a port the API silently failed to bind).
    3. Compile Jac → ``.jac/client/compiled/`` with the *native* runtime
       and stage the entry into ``mobile-rn/jac-app.js``.
    4. Inject the dev API URL into ``mobile-rn/app.json``'s
       ``expo.extra.apiBaseUrl`` so ``Constants.expoConfig`` exposes it
       to the runtime at the very first walker call. Save the original
       text so the ``finally`` block can restore it.
    5. ``adb reverse`` Metro + API ports (best-effort).
    6. Start the Jac API backend (``jaclang start --no_client``).
    7. Start the JacFileWatcher; the callback recompiles native and
       re-stages ``jac-app.js`` — Metro Fast Refresh handles the rest.
    8. Exec ``npx expo start`` blocking; user iterates until Ctrl+C.
    9. On exit (success or signal): stop watcher, kill backend, restore
       app.json.
"""
impl ReactNativeTarget.dev(
    entry_file: Path, project_dir: Path, port: int = 8000, api_port: int = 0
) -> None {
    import from jac_client.plugin.client { JacClient }
    import signal;
    import sys;

    rn_dir = resolve_rn_project_dir(project_dir);
    if not (rn_dir / "package.json").exists() {
        raise RuntimeError(
            "React Native scaffold not found. Run `jac setup react-native` "
            "before `jac start --client react-native --dev`."
        );
    }

    # Port resolution. `port` here mirrors core `jac start --dev --port`
    # semantics: it's the *frontend* port (Metro) and api_port=0 means
    # "use port + 1" — but on RN the frontend port that matters is Metro
    # at 8081 by default, not the value the user passed in. We respect
    # --port for the API and let Metro keep 8081 unless JAC_RN_METRO_PORT
    # overrides; this matches the mental model "Metro is fixed, the API
    # moves around" most RN devs already have.
    api_eff = api_port if api_port > 0 else port;
    metro_port = resolve_metro_port();

    # Visible host: env override > LAN IPv4 > 127.0.0.1. Android emulators
    # use 10.0.2.2 to reach the host's localhost (the build-time injector
    # uses that), but for *physical* devices on the same Wi-Fi we need
    # the dev machine's LAN IP. We default to LAN so the same command
    # works for both — emulators ignore the LAN IP because they hit
    # localhost anyway via adb-reverse.
    host_override = os.environ.get(JAC_RN_DEV_HOST_ENV, "").strip();
    visible_host: str;
    if host_override {
        visible_host = host_override;
    } else {
        lan = detect_lan_ipv4();
        visible_host = lan or "127.0.0.1";
    }

    console.print(
        f"\nReact Native dev (Expo + Metro Fast Refresh) — host {visible_host}",
        style="bold"
    );

    assert_rn_port_available(metro_port, "Metro");
    if api_eff != metro_port {
        assert_rn_port_available(api_eff, "API");
    }

    # Step 1: compile Jac + native runtime. Same path as `build` but no
    # Gradle / prebuild — Metro reads the compiled JS directly via the
    # watchFolders entry the scaffold wrote.
    console.print("  Step 1: Compiling Jac modules + native runtime...", style="muted");
    builder = JacClient.get_client_bundle_builder();
    vite_compiler = builder._get_compiler();
    jac_compiler = vite_compiler.jac_client_compiler;
    compiled_dir = jac_compiler.compiled_dir;
    if compiled_dir is None {
        raise RuntimeError(
            "JacClientCompiler.compiled_dir is None; project config likely "
            "missing. Run `jac setup react-native` first."
        );
    }
    compiled_dir.mkdir(parents=True, exist_ok=True);
    (_, mod, _) = jac_compiler.jac_compiler.compile_module(entry_file);
    if not mod {
        raise RuntimeError(f"Failed to compile client entry module: {entry_file}");
    }
    jac_compiler.compile(
        mod, entry_file, runtime_filename="client_runtime_native.cl.jac"
    );
    console.print("  ✔ Native client modules compiled", style="success");
    lint_unmapped_tags(compiled_dir);

    # Step 2: stage entry + index.ts so the running Metro picks them up.
    entry_module: str = entry_file.stem;
    stage_compiled_entry(compiled_dir, rn_dir, entry_module);
    write_native_entry(rn_dir, "jac-app");

    # Step 3: inject dev API URL into app.json. Constants.expoConfig
    # reads this at runtime via __getApiBaseUrl's second-tier fallback.
    dev_api_url = f"http://{visible_host}:{api_eff}";
    original_app_json = inject_dev_api_base_url(rn_dir, dev_api_url);

    # Step 4: adb reverse so localhost on the emulator hits our host.
    setup_android_port_reverse(metro_port, api_eff);

    # Step 5: backend.
    console.print(f"  Starting Jac API backend on port {api_eff}...", style="muted");
    backend_proc = start_backend_server(entry_file, project_dir, api_eff);

    # Step 6: watcher.
    hot_watcher: any = None;
    if ensure_dev_watchdog() {
        import from jaclang.runtimelib.watcher { JacFileWatcher }

        hmr_handler = _RNHmrHandler(
            compiler=jac_compiler,
            entry_file=entry_file,
            project_dir=project_dir,
            rn_dir=rn_dir,
            entry_module=entry_module
        );
        hot_watcher = JacFileWatcher(watch_paths=[str(project_dir.resolve())]);
        hot_watcher.add_callback(hmr_handler.on_event);
        hot_watcher.start();
    }

    backend_p = backend_proc;
    watcher_p = hot_watcher;

    def cleanup {
        console.print("\n  Stopping Metro, backend, and watcher…", style="muted");
        if watcher_p {
            try {
                watcher_p.stop();
            } except Exception { }
        }
        if backend_p {
            try {
                backend_p.terminate();
                backend_p.wait(timeout=DEV_SUBPROCESS_TIMEOUT_SHORT);
            } except Exception {
                try {
                    backend_p.kill();
                } except Exception { }
            }
        }
        restore_app_json(rn_dir, original_app_json);
        console.print("  ✔ Stopped", style="success");
    }

    def on_signal(signum: int, frame: any) {
        sys.exit(0);
    }
    signal.signal(cast(int, signal.SIGINT), on_signal);
    signal.signal(cast(int, signal.SIGTERM), on_signal);

    console.print(
        f"\n📱 React Native dev ready.\n"
        f"   Metro     : http://{visible_host}:{metro_port}\n"
        f"   API       : {dev_api_url}\n"
        f"   Edit .cl.jac files — Metro will Fast Refresh on save.\n",
        style="bold green"
    );

    try {
        rc = run_expo_start(rn_dir, metro_port, clear_cache=True);
        if rc != 0 {
            console.warning(
                f"  expo start exited with code {rc} — see Metro output above."
            );
        }
    } except KeyboardInterrupt {
        console.print("\n  Interrupted.", style="muted");
    } finally {
        cleanup();
    }
}

"""Build then install + launch on a connected Android device/emulator.

This is the production-mode counterpart to `dev` (no Fast Refresh). The
APK is built, installed via `adb install -r`, and launched via
`adb shell am start`. Requires `adb` on PATH and a connected device or
running emulator.
"""
impl ReactNativeTarget.start(
    entry_file: Path, project_dir: Path, api_port: int = 8000
) -> None {
    apk_path = self.build(entry_file, project_dir, platform="android");

    adb = shutil.which("adb");
    if not adb {
        console.warning(
            "  adb not found on PATH. APK built successfully but "
            "auto-install skipped.\n"
            f"  Install manually: adb install -r {apk_path}"
        );
        return;
    }

    # Resolve the app's package name from app.json so we can launch it. The
    # value lives in expo.android.package which `_build_app_json` sets to
    # ``DEFAULT_APP_ID`` ("com.jac.app"). Reading it back vs. hardcoding
    # means the user's app.json edits propagate to the launch step.
    import json;
    rn_dir = resolve_rn_project_dir(project_dir);
    try {
        app_cfg = json.loads((rn_dir / "app.json").read_text(encoding="utf-8"));
        pkg_name = app_cfg["expo"]["android"]["package"];
    } except Exception as e {
        console.warning(
            f"  Failed to read android.package from app.json ({e}); "
            "skipping auto-launch. APK is installed though."
        );
        pkg_name = None;
    }

    console.print(
        f"  Installing APK on device: adb install -r {apk_path}", style="muted"
    );
    subprocess.run([adb, "install", "-r", str(apk_path)], check=True);

    if pkg_name {
        # `monkey -p <pkg> 1` is the canonical "launch the default activity
        # of this package" incantation on Android — survives package
        # variations across Expo's generated MainActivity naming.
        pkg_str: str = str(pkg_name);
        console.print(f"  Launching: {pkg_str}", style="muted");
        launch_cmd: list[str] = [
            adb,
            "shell",
            "monkey",
            "-p",
            pkg_str,
            "-c",
            "android.intent.category.LAUNCHER",
            "1"
        ];
        subprocess.run(launch_cmd, check=False, capture_output=True);
    }
    console.success("App installed and launched.");
}

"""Watchdog callback bound to the RN dev-loop's compiler state.

Delegates to ``rn_hmr_on_jac_changed`` which does the actual recompile
+ re-stage. The wrapper exists because ``JacFileWatcher.add_callback``
needs a callable, and binding the five required pieces of state via an
object is the simplest cross-thread-safe shape Jac supports.
"""
impl _RNHmrHandler.on_event(evt: FileChangeEvent) -> None {
    rn_hmr_on_jac_changed(
        evt,
        self.compiler,
        self.entry_file,
        self.project_dir,
        self.rn_dir,
        self.entry_module
    );
}
