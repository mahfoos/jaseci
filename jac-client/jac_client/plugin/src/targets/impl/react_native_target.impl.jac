"""Implementation of ReactNativeTarget lifecycle methods.

`setup`  — scaffolds the Expo project under ``mobile-rn/`` and installs
            native deps (idempotent; safe to re-run).
`build`  — JacClientCompiler(native runtime) -> stage compiled JS into
            mobile-rn/ -> expo prebuild -> platform build backend
            (Gradle/xcodebuild/EAS local). Returns the produced artifact.
`dev`    — Metro Fast Refresh loop over JacFileWatcher.
`start`  — Wraps Android ``build`` + ``adb install`` + ``adb shell am start``.
"""

import os;
import shutil;
import subprocess;
import platform as platform_mod;
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
    lint_native_incompatible_usage,
    lint_unmapped_tags,
    run_expo_prebuild,
    run_gradle_assemble,
    run_eas_local_build,
    run_eas_update_opt_in,
    run_xcodebuild_ios,
    stage_native_image_assets,
    stage_compiled_entry,
    strip_css_imports,
    write_native_entry
}
import from jac_client.plugin.src.targets.react_native.config {
    _load_react_native_config,
    _resolve_rn_android_builder,
    _resolve_rn_eas_profile,
    _resolve_rn_eas_update_branch,
    _resolve_rn_eas_update_enabled,
    _resolve_rn_eas_update_message,
    _resolve_rn_ios_builder,
    _resolve_rn_release
}
import from jac_client.plugin.src.targets.react_native.dev {
    SUBPROCESS_TIMEOUT_SHORT as DEV_SUBPROCESS_TIMEOUT_SHORT,
    ensure_watchdog as ensure_dev_watchdog,
    inject_dev_api_base_url,
    resolve_metro_port,
    resolve_rn_port_or_next_available,
    restore_app_json,
    rn_hmr_on_jac_changed,
    run_expo_start,
    setup_android_port_reverse,
    start_backend_server,
    JAC_RN_DEV_HOST_ENV
}
import from jac_client.plugin.src.mobile_dev_host { detect_lan_ipv4 }

glob _ROADMAP_URL = "docs/REACT_NATIVE_ARCHITECTURE.md";

"""Setup the Expo project scaffold and install native deps.

Idempotent: re-running picks up changes to the scaffold templates but
leaves user-edited files (``app/App.tsx``, ``app.json``) alone — see
``_is_scaffold_managed`` in scaffold.jac for the marker-based detection.

It also keeps the platform-aware messaging and EAS.json scaffolding in sync.
"""
impl ReactNativeTarget.setup(project_dir: Path) -> None {
    import from jac_client.plugin.src.targets.react_native.common {
        normalize_rn_platform
    }

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
        "  Build (Android): jac build --client react-native --platform android",
        style="muted"
    );
    console.print(
        "  Build (iOS):     jac build --client react-native --platform ios",
        style="muted"
    );
    console.print(
        "  Dev:             jac start --client react-native --dev", style="muted"
    );
    console.print(
        "  EAS Build:       cd mobile-rn && npx eas build --platform android",
        style="muted"
    );
    console.print(
        "  EAS Update:      cd mobile-rn && npx eas update --branch preview",
        style="muted"
    );
}

"""Build a React Native artifact (Android or iOS).

This method also handles:
  - iOS build path (`xcodebuild` on macOS or EAS local, opt-in)
  - release/debug switch via `[plugins.client.react_native].release`
  - optional EAS Update publish hook (`eas_update=true`)
"""
impl ReactNativeTarget.build(
    entry_file: Path, project_dir: Path, platform: Optional[str] = None
) -> Path {
    import from jac_client.plugin.src.jac_client_compiler { JacClientCompiler }
    import from jac_client.plugin.client { JacClient }

    plat = (platform or "android").lower();
    if plat not in ["android", "ios"] {
        raise ValueError(
            f"Unsupported platform '{plat}' for --client react-native. "
            "Use --platform android or --platform ios."
        );
    }
    rn_cfg = _load_react_native_config(project_dir);
    release = _resolve_rn_release(rn_cfg);
    build_label = "release" if release else "debug";
    ios_builder = _resolve_rn_ios_builder(rn_cfg);

    console.print(
        f"\n📱 Building React Native app ({plat}, {build_label})", style="bold"
    );

    if plat == "ios" and platform_mod.system() != "Darwin" {
        if ios_builder == "xcodebuild" {
            raise RuntimeError(
                "iOS native build requested on non-macOS host.\n"
                "The default iOS builder is xcodebuild, which requires macOS + Xcode.\n"
                "Use one of:\n"
                "  1) Run `jac build --client react-native --platform ios` on macOS\n"
                "  2) Use EAS Build cloud from any OS:\n"
                "     npx eas build --platform ios --profile production --non-interactive\n"
                "  3) Set [plugins.client.react_native].ios_builder = \"eas\" and run "
                "the same EAS command from mobile-rn/"
            );
        }
        raise RuntimeError(
            "iOS EAS local builds require macOS (Xcode toolchain).\n"
            "On Linux/Windows, use EAS Build cloud instead:\n"
            "  npx eas build --platform ios --profile production --non-interactive\n"
            "Run that command inside mobile-rn/."
        );
    }

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
        mod,
        entry_file,
        runtime_filename="client_runtime_native.cl.jac",
        target_name="react-native"
    );
    console.print("  ✔ Jac modules compiled with native runtime", style="success");

    # Step 1b: lint pass — surface unmapped HTML tags before Metro burns
    # cycles bundling something the renderer will fall back on.
    lint_unmapped_tags(compiled_dir);
    lint_native_incompatible_usage(compiled_dir);
    strip_css_imports(compiled_dir);
    stage_native_image_assets(compiled_dir, rn_dir);

    # Step 2: stage compiled entry + write index.ts so Metro picks them up.
    entry_module: str = entry_file.stem;
    stage_compiled_entry(compiled_dir, rn_dir, entry_module);
    write_native_entry(rn_dir, "jac-app");

    # Step 3: expo prebuild — generates android/ or ios/ from app.json.
    console.print(
        f"  Step 2: Running expo prebuild ({plat.capitalize()})...", style="muted"
    );
    run_expo_prebuild(rn_dir, plat);

    # Step 4: native artifact build (Gradle/xcodebuild/EAS local).
    artifact: Path;
    if plat == "android" {
        android_builder = _resolve_rn_android_builder(rn_cfg);
        if android_builder == "eas" {
            eas_profile = _resolve_rn_eas_profile(rn_cfg, release);
            console.print(
                f"  Step 3: Building Android with EAS local (profile={eas_profile})...",
                style="muted"
            );
            artifact = run_eas_local_build(
                rn_dir, platform="android", profile=eas_profile, release=release
            );
        } else {
            console.print("  Step 3: Building Android with Gradle...", style="muted");
            artifact = run_gradle_assemble(rn_dir, release=release);
        }
    } elif ios_builder == "eas" {
        eas_profile = _resolve_rn_eas_profile(rn_cfg, release);
        console.print(
            f"  Step 3: Building iOS with EAS local (profile={eas_profile})...",
            style="muted"
        );
        artifact = run_eas_local_build(
            rn_dir, platform="ios", profile=eas_profile, release=release
        );
    } else {
        console.print("  Step 3: Building iOS with xcodebuild...", style="muted");
        artifact = run_xcodebuild_ios(rn_dir, release=release);
    }

    if _resolve_rn_eas_update_enabled(rn_cfg) {
        update_branch = _resolve_rn_eas_update_branch(rn_cfg, release);
        update_msg = _resolve_rn_eas_update_message(rn_cfg);
        run_eas_update_opt_in(
            rn_dir, platform=plat, branch=update_branch, message=update_msg
        );
    }

    console.success(f"React Native build complete: {artifact}");
    if plat == "android" {
        console.print("\nInstall with: adb install -r " + str(artifact), style="muted");
    } else {
        console.print(
            "\nFor signing/provisioning and distribution, follow Expo iOS build docs:\n"
            "  https://docs.expo.dev/build-reference/ios-builds/",
            style="muted"
        );
    }
    return artifact;
}

"""Start the Metro dev loop with Fast Refresh.

Orchestration (Android-only for v1; iOS sim is best-effort once Metro is
up because Expo's CLI handles both, but our adb-reverse + emulator-host
defaults assume Android):

    1. Resolve dev host (env override > LAN IPv4 > 127.0.0.1).
    2. Pick Metro port + API port; if either is busy, increment until we
       find a free one so adb-reverse + app.json stay aligned with what
       actually binds.
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

    # Port resolution. In the react-native dev loop, `--port` is treated
    # as the preferred API port. Metro keeps its own preferred port
    # (8081 by default, or JAC_RN_METRO_PORT). If either preferred port is
    # occupied we probe upward (+1, +2, ...) until we find free ports,
    # keeping Metro/API distinct so adb reverse + app.json stay aligned.
    requested_api = api_port if api_port > 0 else port;
    requested_metro = resolve_metro_port();
    metro_port = resolve_rn_port_or_next_available(requested_metro, "Metro");
    api_eff = resolve_rn_port_or_next_available(
        requested_api, "API", reserved=[metro_port]
    );

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
        mod,
        entry_file,
        runtime_filename="client_runtime_native.cl.jac",
        target_name="react-native"
    );
    console.print("  ✔ Native client modules compiled", style="success");
    lint_unmapped_tags(compiled_dir);
    lint_native_incompatible_usage(compiled_dir);
    strip_css_imports(compiled_dir);
    stage_native_image_assets(compiled_dir, rn_dir);

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

"""Build then install + launch on a connected device/emulator.

Android: APK is built, installed via ``adb install -r``, and launched via
``adb shell am start``.

iOS: IPA is built (requires macOS), installed on a booted iOS simulator
via ``xcrun simctl``, and launched via ``xcrun simctl launch``.
Requires Xcode CLI tools on PATH.
"""
impl ReactNativeTarget.start(
    entry_file: Path, project_dir: Path, api_port: int = 8000
) -> None {
    import platform as platform_mod;
    import from jac_client.plugin.src.targets.react_native.common {
        normalize_rn_platform
    }

    # Default platform: Android. Override via jac.toml or --platform.
    rn_cfg = _load_react_native_config(project_dir);
    default_plat = str(rn_cfg.get("default_platform", "") or "android").strip().lower();
    plat = normalize_rn_platform(default_plat);

    artifact = self.build(entry_file, project_dir, platform=plat);

    if plat == "ios" {
        _start_ios(artifact, project_dir);
    } else {
        _start_android(artifact, project_dir);
    }
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

"""Install and launch an Android APK on a connected device/emulator."""
def _start_android(apk_path: Path, project_dir: Path) -> None {
    import json;
    import from jac_client.plugin.src.targets.react_native.common {
        resolve_rn_project_dir
    }
    adb = shutil.which("adb");
    if not adb {
        console.warning(
            "  adb not found on PATH. APK built successfully but "
            "auto-install skipped.\n"
            f"  Install manually: adb install -r {apk_path}"
        );
        return;
    }

    rn_dir = resolve_rn_project_dir(project_dir);
    pkg_name: str | None = None;
    try {
        app_cfg = json.loads((rn_dir / "app.json").read_text(encoding="utf-8"));
        pkg_name = app_cfg["expo"]["android"]["package"];
    } except Exception as e {
        console.warning(
            f"  Failed to read android.package from app.json ({e}); "
            "skipping auto-launch. APK is installed though."
        );
    }

    console.print(
        f"  Installing APK on device: adb install -r {apk_path}", style="muted"
    );
    subprocess.run([adb, "install", "-r", str(apk_path)], check=True);

    if pkg_name {
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

"""Install and launch an iOS IPA on a booted simulator.

Requires macOS + Xcode CLI tools. If no simulator is booted, attempts to
boot the first available iPhone simulator. The IPA is installed via
``xcrun simctl addmedia`` (which handles .ipa bundles) and launched by
bundle identifier.
"""
def _start_ios(ipa_path: Path, project_dir: Path) {
    import json;
    import from jac_client.plugin.src.targets.react_native.common {
        resolve_rn_project_dir
    }
    import platform as platform_mod;
    if platform_mod.system() != "Darwin" {
        raise RuntimeError(
            "iOS install & launch requires macOS with Xcode.\n"
            "On Linux/Windows, use EAS Build cloud and TestFlight:\n"
            "  npx eas build --platform ios --profile preview\n"
            "  npx eas submit --platform ios\n"
            "Run inside mobile-rn/."
        );
    }

    xcrun = shutil.which("xcrun");
    if not xcrun {
        raise RuntimeError(
            "xcrun not found. Install Xcode CLI tools:\n" "  xcode-select --install"
        );
    }

    rn_dir = resolve_rn_project_dir(project_dir);
    bundle_id: str | None = None;
    try {
        app_cfg = json.loads((rn_dir / "app.json").read_text(encoding="utf-8"));
        bundle_id = app_cfg["expo"]["ios"]["bundleIdentifier"];
    } except Exception as e {
        console.warning(
            f"  Failed to read ios.bundleIdentifier from app.json ({e}); "
            "will attempt install without auto-launch."
        );
    }

    # Find or boot a simulator.
    sim_result = subprocess.run(
        [xcrun, "simctl", "list", "devices", "-j"],
        capture_output=True,
        text=True,
        check=True
    );
    import json as json_mod;
    sim_data = json_mod.loads(sim_result.stdout);
    devices = sim_data.get("devices", {});

    booted_udid: str | None = None;
    for (runtime_key, device_list) in devices.items() {
        for dev in device_list {
            if dev.get("isAvailable") and dev.get("state") == "Booted" {
                booted_udid = dev["udid"];
                break;
            }
        }
        if booted_udid {
            break;
        }
    }

    if not booted_udid {
        # Boot the first available iPhone simulator.
        target_udid: str | None = None;
        for (runtime_key, device_list) in devices.items() {
            if "iOS" not in runtime_key {
                continue;
            }
            for dev in device_list {
                if dev.get("isAvailable") and "iPhone" in dev.get("name", "") {
                    target_udid = dev["udid"];
                    break;
                }
            }
            if target_udid {
                break;
            }
        }
        if target_udid {
            console.print(f"  Booting simulator {target_udid}...", style="muted");
            subprocess.run(
                [xcrun, "simctl", "boot", target_udid], check=True, capture_output=True
            );
            booted_udid = target_udid;
        } else {
            raise RuntimeError(
                "No iOS simulator available. Open Xcode > Window > Devices "
                "and Simulators to create one."
            );
        }
    }

    console.print(f"  Installing IPA on simulator {booted_udid}...", style="muted");
    subprocess.run(
        [xcrun, "simctl", "addmedia", booted_udid, str(ipa_path)],
        check=False,
        capture_output=True
    );

    if bundle_id {
        bid: str = str(bundle_id);
        console.print(f"  Launching: {bid}", style="muted");
        subprocess.run(
            [xcrun, "simctl", "launch", booted_udid, bid],
            check=False,
            capture_output=True
        );
    }
    console.success("iOS app installed and launched on simulator.");
}
