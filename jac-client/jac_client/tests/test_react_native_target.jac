"""Tests for the React Native target skeleton.

The build flow itself is not implemented yet (Phase 1 follow-ups), so these
tests cover the *discovery surface* — the contract that ``jac build --client
react-native`` resolves to a registered target, that the native entry
generator is wired into the registry, and that calling unimplemented
lifecycle methods raises a loud, well-formed error pointing at the roadmap.

The pattern mirrors ``test_mobile_target.jac``: file-existence checks via
source scan, plus runtime assertions on the registry and entry-generator
behavior. Source scans guard against silent regressions (e.g. someone
deleting the target file) without standing up a fixture project.
"""

import os;
import from pathlib { Path }
import pytest;

glob _plugin_dir = Path(os.path.dirname(__file__)).parent / "plugin";

test "react native target files exist" {
    target_jac = _plugin_dir / "src" / "targets" / "react_native_target.jac";
    target_impl = (
        _plugin_dir / "src" / "targets" / "impl" / "react_native_target.impl.jac"
    );
    entry_jac = _plugin_dir / "src" / "entry_generators" / "native_entry.jac";

    assert target_jac.exists() , f"react_native_target.jac not found at {target_jac}";
    assert target_impl.exists() , (
        f"react_native_target.impl.jac not found at {target_impl}"
    );
    assert entry_jac.exists() , f"native_entry.jac not found at {entry_jac}";

    content = target_jac.read_text();
    assert "obj ReactNativeTarget(ClientTarget)" in content , (
        "ReactNativeTarget must extend ClientTarget directly (D3), not WebTarget"
    );
    # D3 belt-and-suspenders: no `WebTarget` in any import/inheritance position.
    # Docstrings explaining the decision are fine, so we don't ban the literal
    # token, only the import/extension forms.
    assert "import from jac_client.plugin.src.targets.web_target" not in content;
    assert "ReactNativeTarget(WebTarget)" not in content;
    assert 'name: str = "react-native"' in content;
    assert "requires_setup: bool = True" in content;
    assert 'config_section: str = "react_native"' in content;
}

test "target type parser supports react-native and aliases" {
    registry_path = _plugin_dir / "src" / "targets" / "registry.jac";
    content = registry_path.read_text();

    assert 'REACT_NATIVE = "react-native"' in content;
    # Aliases ergonomic enough to be worth documenting via assertion — keeps
    # the canonical-name decision (Q1) honest while still accepting common
    # spellings users will reach for.
    assert "react-native" in content;
    assert "react_native" in content;
    assert '"rn"' in content;
    assert "return TargetType.REACT_NATIVE" in content;
}

test "target factory supports react native target" {
    impl_path = _plugin_dir / "src" / "targets" / "impl" / "registry.impl.jac";
    content = impl_path.read_text();

    assert "elif target_type == TargetType.REACT_NATIVE" in content;
    assert "ReactNativeTarget" in content;
    assert "TargetType.REACT_NATIVE" in content;
}

test "register.jac registers the react native target and imports native entry" {
    register_path = _plugin_dir / "src" / "targets" / "register.jac";
    content = register_path.read_text();

    assert "ReactNativeTarget" in content;
    # Side-effect import is the documented mechanism for entry-generator
    # registration; missing it means `jac build --client react-native` could
    # silently find no native generator at runtime.
    assert "from jac_client.plugin.src.entry_generators.native_entry" in content;
    assert "build_native_entry_script" in content;
    assert "react_native_target = ReactNativeTarget()" in content;
    assert "registry.register(react_native_target)" in content;
}

test "target factory resolves react-native by canonical name" {
    import from jac_client.plugin.src.targets.registry {
        get_target_factory,
        get_target_type,
        TargetType
    }

    assert get_target_type("react-native") == TargetType.REACT_NATIVE;
    assert get_target_type("react_native") == TargetType.REACT_NATIVE;
    assert get_target_type("rn") == TargetType.REACT_NATIVE;
    assert get_target_type("REACT-NATIVE") == TargetType.REACT_NATIVE;

    factory = get_target_factory();
    target = factory.create("react-native", Path.cwd());
    assert target.name == "react-native";
    assert target.requires_setup == True;
    assert target.default == False;
    assert target.config_section == "react_native";
}

test "react native dev fails fast when scaffold is missing" {
    # Phase 2 ships the Metro Fast Refresh loop, so `dev` no longer raises
    # NotImplementedError. Instead, calling it without a scaffold must
    # raise a RuntimeError pointing the user at `jac setup react-native`
    # — the contract is "explicit failure, never silent partial work".
    import tempfile;
    import from jac_client.plugin.src.targets.registry { get_target_factory }

    factory = get_target_factory();
    with tempfile.TemporaryDirectory() as tmp {
        target = factory.create("react-native", Path(tmp));
        try {
            target.dev(Path(tmp) / "main.jac", Path(tmp));
            assert False , "expected dev() to raise when scaffold is missing";
        } except NotImplementedError as e {
            assert False , (
                "dev() should no longer raise NotImplementedError now "
                f"that Phase 2 has landed; got: {e}"
            );
        } except RuntimeError as e {
            assert "jac setup react-native" in str(e) , (
                f"missing-scaffold error must point at setup command: {e}"
            );
        }
    }
}

test "react native build source includes phase 4 ios and release wiring" {
    # Phase 4 replaces the old iOS NotImplementedError path with real
    # orchestration. Keep this as a source-level contract check so the
    # test suite stays deterministic (no Node/Xcode/EAS requirement).
    impl_path = _plugin_dir / "src" / "targets" / "impl" / "react_native_target.impl.jac";
    build_path = _plugin_dir / "src" / "targets" / "react_native" / "build.jac";
    cfg_path = _plugin_dir / "src" / "targets" / "react_native" / "config.jac";

    impl_content = impl_path.read_text();
    build_content = build_path.read_text();
    cfg_content = cfg_path.read_text();

    build_section = impl_content.split("impl ReactNativeTarget.build")[1].split(
        "impl ReactNativeTarget.dev"
    )[0];
    assert "NotImplementedError" not in build_section;
    assert "run_xcodebuild_ios" in build_section;
    assert "run_eas_local_build" in build_section;
    assert "_resolve_rn_release" in build_section;
    assert "_resolve_rn_ios_builder" in build_section;
    assert "_resolve_rn_android_builder" in build_section;
    assert "_resolve_rn_eas_update_enabled" in build_section;
    assert "iOS native build requested on non-macOS host" in build_section;
    assert "EAS Build cloud" in build_section;

    assert "def run_xcodebuild_ios" in build_content;
    assert "def run_eas_local_build" in build_content;
    assert "def run_eas_update_opt_in" in build_content;
    assert "def _package_ios_app_as_ipa" in build_content;
    assert ".ipa" in build_content;
    assert "expo prebuild" in build_content;

    assert "def _resolve_rn_release" in cfg_content;
    assert "def _resolve_rn_ios_builder" in cfg_content;
    assert "def _resolve_rn_android_builder" in cfg_content;
}

test "react native target exposes the documented Phase 1 surface" {
    # Sanity check on the API shape — the target instance has setup/build/
    # dev/start methods, name and config_section match D11 conventions, and
    # output_dir points at the Android Gradle output location.
    import from jac_client.plugin.src.targets.registry { get_target_factory }

    factory = get_target_factory();
    target = factory.create("react-native", Path.cwd());

    assert hasattr(target, "setup");
    assert hasattr(target, "build");
    assert hasattr(target, "dev");
    assert hasattr(target, "start");
    assert target.name == "react-native";
    assert target.config_section == "react_native";
    assert "mobile-rn" in str(target.output_dir);
}

test "native entry generator is registered through the runtime registry" {
    # `with entry { ... }` blocks run once per process on first import. Use
    # importlib.reload to force a fresh registration — same pattern as
    # test_entry_generators.jac uses for the web generator.
    import importlib;
    import from jaclang.runtimelib.entry_generators {
        get_entry_generator,
        has_entry_generator,
        clear_entry_generators
    }

    clear_entry_generators();
    assert not has_entry_generator("native");
    import jac_client.plugin.src.entry_generators.native_entry as native_entry_mod;
    importlib.reload(native_entry_mod);
    assert has_entry_generator("native");

    fn = get_entry_generator("native");
    script = fn("main");
    # Acceptance: emitted script registers the imported `app` against
    # AppRegistry under the canonical Expo root component name. These three
    # invariants together define the entry-script contract.
    assert "AppRegistry" in script;
    assert "registerComponent" in script;
    assert 'from "./main.js"' in script;
    assert "app as JacApp" in script;
    # Round-trip equality check: the registered fn must be the same function
    # the module exports, not a stale closure or shim.
    direct = native_entry_mod.build_native_entry_script("main");
    assert direct == script;
}

test "native runtime file ships parallel to the web runtime" {
    # D9: shared logic lives in client_runtime_core; native is platform adapters.
    runtime_core = _plugin_dir / "client_runtime_core.cl.jac";
    runtime_core_impl = _plugin_dir / "impl" / "client_runtime_core.impl.jac";
    runtime_native = _plugin_dir / "client_runtime_native.cl.jac";
    runtime_native_impl = _plugin_dir / "impl" / "client_runtime_native.impl.jac";

    assert runtime_core.exists() , (
        f"client_runtime_core.cl.jac not found at {runtime_core}"
    );
    assert runtime_core_impl.exists();
    assert runtime_native.exists() , (
        f"client_runtime_native.cl.jac not found at {runtime_native}"
    );
    assert runtime_native_impl.exists();
    assert "import from client_runtime_core" in runtime_native.read_text();

    core_content = runtime_core.read_text();
    cl_content = runtime_native.read_text();
    impl_content = runtime_native_impl.read_text();

    # Renderer dispatch lives in core (R3); native supplies __jacNativeCreate.
    assert "__jacJsx" in core_content;
    assert "__jacRegisterRenderer" in core_content;
    assert "__jacNativeCreate" in cl_content;
    assert "__jacNativeCreate" in impl_content;
    # Must import from react-native, not react-dom / react-router.
    assert "from 'react-native'" in cl_content;
    assert "@react-navigation/native" in cl_content;
    assert "@react-navigation/native-stack" in cl_content;
    assert "expo-secure-store" in cl_content;
    forbidden_imports = [
        "from 'react-dom",
        "from 'react-router-dom'",
        "from \"react-dom",
        "from \"react-router-dom\""
    ];
    for needle in forbidden_imports {
        assert needle not in cl_content , (
            f"native runtime leaked web import: {needle!r}"
        );
        assert needle not in impl_content , (
            f"native runtime impl leaked web import: {needle!r}"
        );
    }
    # Symbols only valid in DOM context must not appear as identifiers in
    # the impl (comments are fine — they document the contrast).
    forbidden_symbols = ["createRoot(", "BrowserRouter(", "document.getElementById"];
    for needle in forbidden_symbols {
        assert needle not in impl_content , (
            f"native runtime impl uses web-only symbol: {needle!r}"
        );
    }
    # Phase 3: Router surface is implemented via React Navigation; no
    # placeholder stubs should remain.
    assert "Phase 3 features for" not in impl_content;
    assert "__nativeRouterStub" not in cl_content;
    assert "__nativeRouterStub" not in impl_content;
    # Q8 follow-up: img src -> RN Image source adaptation exists.
    assert "_adaptImageProps" in impl_content;
    assert 'uri.startswith("/")' in impl_content;
    assert "_RELATIVE_IMG_SRC_WARNED" in impl_content;
    assert "__JAC_RN_ASSET_MAP__" in impl_content;
    assert "__jac_rn_asset__:" in impl_content;
    assert 'field_type == "select"' in impl_content;
    assert 'field_type == "radio"' in impl_content;
    assert "_getEnumOptions" in impl_content;
}

test "JacClientCompiler accepts runtime_filename to select native runtime" {
    # The compiler's `compile_runtime_utils` and `compile` now both accept
    # `runtime_filename` so the React Native target can swap in the native
    # runtime without touching any bundler glue. Source-level contract check.
    src_path = _plugin_dir / "src" / "jac_client_compiler.jac";
    impl_path = _plugin_dir / "src" / "impl" / "jac_client_compiler.impl.jac";
    src_content = src_path.read_text();
    impl_content = impl_path.read_text();

    assert "runtime_filename" in src_content , (
        "JacClientCompiler must declare runtime_filename parameter"
    );
    assert "runtime_filename" in impl_content;
    assert "target_name" in src_content;
    assert "target_name" in impl_content;
    assert ".native.cl.jac" in src_content;
    assert ".native.cl.jac" in (_plugin_dir / "src" / "compiler.jac").read_text();
    assert src_content.index(".native.cl.jac") < src_content.index(".cl.jac") , (
        "COMPOUND_EXTENSIONS must put .native.cl.jac before .cl.jac so "
        "Header.native.cl.jac maps to Header.js (not Header.native.js)."
    );
    assert 'client_runtime.cl.jac' in src_content;
    assert "client_runtime_core.cl.jac" in impl_content , (
        "compile_runtime_utils must bundle client_runtime_core (D9)"
    );
    assert "_bundle_runtime_js" in impl_content;
}

test "react native compiler selects .native.cl.jac variants when available" {
    impl_path = _plugin_dir / "src" / "impl" / "jac_client_compiler.impl.jac";
    impl_content = impl_path.read_text();

    assert "target_name == \"react-native\"" in impl_content;
    assert "native_candidate" in impl_content;
    assert ".native.cl.jac" in impl_content;
    assert "target_name=target_name" in impl_content;
    assert "_scan_and_compile_pages(" in impl_content;
    assert "target_name=target_name" in impl_content.split("_scan_and_compile_pages(")[
        1
    ];
}

test "react native target compile calls set target_name to react-native" {
    target_impl = _plugin_dir / "src" / "targets" / "impl" / "react_native_target.impl.jac";
    dev_src = _plugin_dir / "src" / "targets" / "react_native" / "dev.jac";
    target_content = target_impl.read_text();
    dev_content = dev_src.read_text();

    assert "target_name=\"react-native\"" in target_content;
    assert "target_name=\"react-native\"" in dev_content;
}

test "target selection keeps web and native entry/runtime paths separate" {
    # Phase 3 invariant: target flag controls runtime + entry generator.
    # RN must call the native generator/runtime; web must keep web defaults.
    rn_build_src = _plugin_dir / "src" / "targets" / "react_native" / "build.jac";
    rn_impl_src = (
        _plugin_dir / "src" / "targets" / "impl" / "react_native_target.impl.jac"
    );
    web_compiler_impl = _plugin_dir / "src" / "impl" / "compiler.impl.jac";

    rn_build_content = rn_build_src.read_text();
    rn_impl_content = rn_impl_src.read_text();
    web_content = web_compiler_impl.read_text();

    assert 'get_entry_generator("native")' in rn_build_content;
    assert 'runtime_filename="client_runtime_native.cl.jac"' in rn_impl_content;
    assert 'get_entry_generator("web")' in web_content;
    # Web compile path should not force native runtime.
    assert 'runtime_filename="client_runtime_native.cl.jac"' not in web_content;
}

test "react native scaffold writes Expo project files" {
    # Smoke-test the scaffold writer end to end: setup an empty project dir,
    # run write_expo_scaffold, assert the canonical files exist and that the
    # generated metro.config.js points @jac/runtime at the compiled runtime.
    import tempfile;
    import from jac_client.plugin.src.targets.react_native.scaffold {
        write_expo_scaffold
    }

    with tempfile.TemporaryDirectory() as tmp {
        project_root = Path(tmp);
        rn_dir = project_root / "mobile-rn";
        write_expo_scaffold(rn_dir, project_root);
        assert (rn_dir / "package.json").exists();
        assert (rn_dir / "app.json").exists();
        assert (rn_dir / "metro.config.js").exists();
        assert (rn_dir / "babel.config.js").exists();
        assert (rn_dir / "index.ts").exists();
        assert (rn_dir / "app" / "App.tsx").exists();
        metro_content = (rn_dir / "metro.config.js").read_text();
        pkg_content = (rn_dir / "package.json").read_text();
        app_content = (rn_dir / "app" / "App.tsx").read_text();
        # Metro must alias @jac/runtime to the compiled runtime so the
        # bundle gets the native variant at resolution time.
        assert "@jac/runtime" in metro_content;
        assert "client_runtime.js" in metro_content;
        assert "watchFolders" in metro_content;
        assert "@react-navigation/native" in pkg_content;
        assert "@react-navigation/native-stack" in pkg_content;
        assert "react-native-screens" in pkg_content;
        assert "from '../jac-app'" in app_content;
        app_json = (rn_dir / "app.json").read_text();
        # D8: New Architecture + Hermes from day one.
        assert "newArchEnabled" in app_json;
        assert "hermes" in app_json;
    }
}

test "scaffold preserves user-edited files on re-run" {
    # Re-running setup must not stomp on user customizations. The scaffold
    # marker line opts a file into auto-refresh; removing it pins the file.
    import tempfile;
    import from jac_client.plugin.src.targets.react_native.scaffold {
        write_expo_scaffold
    }

    with tempfile.TemporaryDirectory() as tmp {
        project_root = Path(tmp);
        rn_dir = project_root / "mobile-rn";
        write_expo_scaffold(rn_dir, project_root);
        # Simulate user editing App.tsx and removing the scaffold marker.
        app_tsx = rn_dir / "app" / "App.tsx";
        custom = "// my own shell\nexport default function App() { return null; }\n";
        app_tsx.write_text(custom);
        # Re-run scaffold. App.tsx should be left alone; metro.config.js
        # (still marker-managed) should be refreshed.
        write_expo_scaffold(rn_dir, project_root);
        assert app_tsx.read_text() == custom , (
            "scaffold clobbered user-edited App.tsx"
        );
        # metro.config.js must still be present (refreshed)
        assert (rn_dir / "metro.config.js").exists();
    }
}

test "lint_unmapped_tags flags HTML tags outside the documented map" {
    # The compile-time lint pass (D10) scans compiled JS for __jacJsx calls
    # using HTML tags outside the supported subset. Construct a fake
    # compiled dir with both supported and unsupported tags and assert
    # the lint result.
    import tempfile;
    import from jac_client.plugin.src.targets.react_native.build { lint_unmapped_tags }

    with tempfile.TemporaryDirectory() as tmp {
        compiled = Path(tmp);
        # `div` and `button` are supported; `marquee` and `details` aren't.
        (compiled / "user.js").write_text(
            '__jacJsx("div", {}, [__jacJsx("button", {}, ["click"])]);\n'
            '__jacJsx("marquee", {}, ["whee"]);\n'
            '__jacJsx("details", {}, []);\n'
        );
        # client_runtime.js should be ignored (it contains the tag-map
        # literals which would generate false positives).
        (compiled / "client_runtime.js").write_text(
            '__jacJsx("marquee", {}, []); // tag-map self-test\n'
        );
        unmapped = lint_unmapped_tags(compiled);
        assert "marquee" in unmapped;
        assert "details" in unmapped;
        assert "div" not in unmapped;
        assert "button" not in unmapped;
    }
}

test "lint_native_incompatible_usage flags css imports and web globals" {
    import tempfile;
    import from jac_client.plugin.src.targets.react_native.build {
        lint_native_incompatible_usage
    }

    with tempfile.TemporaryDirectory() as tmp {
        compiled = Path(tmp);
        (compiled / "feature.js").write_text(
            'import "./styles.css";\n'
            'const w = window.location.href;\n'
            'document.title = "x";\n'
            'localStorage.setItem("a", "b");\n'
            '__jacJsx("img", {src: "./avatar.png"}, []);\n'
            '__jacJsx("img", {src: "/static/assets/logo.png"}, []);\n'
        );
        # Runtime file is excluded from lint scanning by design.
        (compiled / "client_runtime.js").write_text(
            'import "./ignored.css";\nconst x = window;\n'
        );
        result = lint_native_incompatible_usage(compiled);
        assert "./styles.css" in result["css_imports"];
        assert "window" in result["web_globals"];
        assert "document" in result["web_globals"];
        assert "localStorage" in result["web_globals"];
        assert "ignored.css" not in result["css_imports"];
        assert "./avatar.png" in result["relative_img_srcs"];
        assert "./avatar.png" in result["unresolved_relative_img_srcs"];
        assert "/static/assets/logo.png" not in result["relative_img_srcs"];
    }
}

test "stage_native_image_assets rewrites relative img src to Metro token map" {
    import tempfile;
    import from jac_client.plugin.src.targets.react_native.build {
        stage_native_image_assets
    }

    with tempfile.TemporaryDirectory() as tmp {
        tmp_path = Path(tmp);
        compiled = tmp_path / "compiled";
        rn_dir = tmp_path / "mobile-rn";
        compiled.mkdir(parents=True);
        rn_dir.mkdir(parents=True);
        (compiled / "avatar.png").write_bytes(b"pngbytes");
        (compiled / "feature.js").write_text(
            '__jacJsx("img", {src: "./avatar.png"}, []);\n'
        );
        result = stage_native_image_assets(compiled, rn_dir);
        rewritten = (compiled / "feature.js").read_text();
        registry = (rn_dir / "jac-asset-registry.js").read_text();
        assert result["bundled_count"] == 1;
        assert result["unresolved_relative_img_srcs"] == [];
        assert "__jac_rn_asset__:" in rewritten;
        assert "require('./jac-assets/" in registry;
        assert (rn_dir / "jac-assets").exists();
        staged_assets = list((rn_dir / "jac-assets").glob("*"));
        assert len(staged_assets) == 1;
    }
}

test "stage_compiled_entry injects asset registry import" {
    import tempfile;
    import from jac_client.plugin.src.targets.react_native.build {
        stage_compiled_entry,
        stage_native_image_assets
    }

    with tempfile.TemporaryDirectory() as tmp {
        tmp_path = Path(tmp);
        compiled = tmp_path / "compiled";
        rn_dir = tmp_path / "mobile-rn";
        compiled.mkdir(parents=True);
        rn_dir.mkdir(parents=True);
        (compiled / "main.js").write_text("export const app = () => null;\n");
        stage_native_image_assets(compiled, rn_dir);
        stage_compiled_entry(compiled, rn_dir, "main");
        staged = (rn_dir / "jac-app.js").read_text();
        assert "import './jac-asset-registry';" in staged;
    }
}

test "phase 3 multiscreen fixture exists with auth routes forms and walker call" {
    fixture_dir = Path(__file__).parent / "fixtures" / "react_native_multiscreen";
    assert fixture_dir.exists();
    assert (fixture_dir / "main.jac").exists();
    assert (fixture_dir / "jac.toml").exists();

    main_content = (fixture_dir / "main.jac").read_text();
    assert "AuthGuard" in main_content;
    assert "JacForm" in main_content;
    assert "Router" in main_content;
    assert "Route" in main_content;
    assert "root spawn whoami()" in main_content;
    assert 'path="detail/:id"' in main_content;
}

test "phase 2 dev helpers exist and are importable" {
    # The dev module is the entry point for `jac start --client react-native
    # --dev`. Importing it must succeed and expose the helper surface the
    # target impl depends on; the impl uses each by name, so a missing
    # export would be a build-time failure for users.
    import from jac_client.plugin.src.targets.react_native.dev {
        DEFAULT_METRO_PORT,
        JAC_RN_DEV_HOST_ENV,
        JAC_RN_METRO_PORT_ENV,
        assert_rn_port_available,
        build_expo_start_argv,
        ensure_watchdog,
        inject_dev_api_base_url,
        resolve_metro_port,
        restore_app_json,
        rn_hmr_on_jac_changed,
        run_expo_start,
        setup_android_port_reverse,
        start_backend_server
    }

    assert DEFAULT_METRO_PORT == 8081 , (
        "Metro's documented default is 8081; changing it without a "
        "corresponding scaffold update would break adb-reverse + Expo CLI."
    );
    assert JAC_RN_METRO_PORT_ENV == "JAC_RN_METRO_PORT";
    assert JAC_RN_DEV_HOST_ENV == "JAC_RN_DEV_HOST";
}

test "resolve_metro_port honors env override over cli value" {
    import os;
    import from jac_client.plugin.src.targets.react_native.dev {
        JAC_RN_METRO_PORT_ENV,
        resolve_metro_port
    }

    prev = os.environ.get(JAC_RN_METRO_PORT_ENV, None);
    try {
        os.environ[JAC_RN_METRO_PORT_ENV] = "19999";
        assert resolve_metro_port(8081) == 19999;
        os.environ[JAC_RN_METRO_PORT_ENV] = "";
        assert resolve_metro_port(8081) == 8081;
    } finally {
        if prev is None {
            if JAC_RN_METRO_PORT_ENV in os.environ {
                del os.environ[JAC_RN_METRO_PORT_ENV];
            }
        } else {
            os.environ[JAC_RN_METRO_PORT_ENV] = prev;
        }
    }
}

test "build_expo_start_argv emits expected metro flags" {
    # Pure helper — easy to assert and the surface most likely to drift
    # if someone tweaks the dev loop without rerunning the smoke test.
    import from jac_client.plugin.src.targets.react_native.dev { build_expo_start_argv }

    argv = build_expo_start_argv(8081, clear_cache=True);
    assert "expo" in argv;
    assert "start" in argv;
    assert "--port" in argv;
    assert "8081" in argv;
    assert "--clear" in argv;

    argv2 = build_expo_start_argv(9090, clear_cache=False);
    assert "9090" in argv2;
    assert "--clear" not in argv2;
}

test "inject_dev_api_base_url rewrites app.json and roundtrips" {
    # Verifies the round-trip invariant: inject returns the original raw
    # bytes; restore puts them back verbatim. This is what guarantees the
    # user's pre-dev app.json (often hand-edited extra fields) survives a
    # `jac start --dev` session unscathed.
    import json;
    import tempfile;
    import from jac_client.plugin.src.targets.react_native.dev {
        inject_dev_api_base_url,
        restore_app_json
    }

    with tempfile.TemporaryDirectory() as tmp {
        rn_dir = Path(tmp);
        original_cfg = {
            "expo": {
                "name": "main",
                "extra": {"apiBaseUrl": "http://baked.example", "feature": True}
            }
        };
        app_json = rn_dir / "app.json";
        original_text = json.dumps(original_cfg, indent=2) + "\n";
        app_json.write_text(original_text, encoding="utf-8");
        returned = inject_dev_api_base_url(rn_dir, "http://10.0.0.5:8000");
        assert returned == original_text;
        after = json.loads(app_json.read_text(encoding="utf-8"));
        assert after["expo"]["extra"]["apiBaseUrl"] == "http://10.0.0.5:8000";
        # Other fields preserved (we only touch apiBaseUrl).
        assert after["expo"]["extra"]["feature"] == True;
        assert after["expo"]["name"] == "main";
        restore_app_json(rn_dir, returned);
        assert app_json.read_text(encoding="utf-8") == original_text;
    }
}

test "inject_dev_api_base_url no-ops gracefully on missing app.json" {
    import tempfile;
    import from jac_client.plugin.src.targets.react_native.dev {
        inject_dev_api_base_url,
        restore_app_json
    }

    with tempfile.TemporaryDirectory() as tmp {
        rn_dir = Path(tmp);
        # No app.json written. inject must return None so the caller's
        # `finally restore_app_json(...)` is a no-op rather than writing
        # garbage to a file that should stay absent.
        result = inject_dev_api_base_url(rn_dir, "http://localhost:8000");
        assert result is None;
        # restore must also no-op cleanly given None.
        restore_app_json(rn_dir, None);
        assert not (rn_dir / "app.json").exists();
    }
}

test "_RNHmrHandler obj is declared and wired in target module" {
    # Source-level check that the dev loop's watcher binding exists; a
    # missing handler would silently disable Fast Refresh recompiles.
    target_jac = _plugin_dir / "src" / "targets" / "react_native_target.jac";
    impl_jac = (
        _plugin_dir / "src" / "targets" / "impl" / "react_native_target.impl.jac"
    );
    target_content = target_jac.read_text();
    impl_content = impl_jac.read_text();

    assert "obj _RNHmrHandler" in target_content;
    assert "rn_dir: Path" in target_content;
    assert "entry_module: str" in target_content;
    assert "impl _RNHmrHandler.on_event" in impl_content;
    assert "rn_hmr_on_jac_changed" in impl_content;
    # Dev impl must invoke the real flow, not the old NotImplementedError.
    assert "raise NotImplementedError" not in impl_content.split(
        "impl ReactNativeTarget.dev"
    )[1].split(
        "impl ReactNativeTarget.start"
    )[0];
    assert "run_expo_start" in impl_content;
    assert "JacFileWatcher" in impl_content;
}

test "native entry generator omits web-only imports" {
    # The whole point of the per-target generator (R2) is to keep DOM and
    # react-router out of the native bundle. Regress-guard those.
    import importlib;
    import jac_client.plugin.src.entry_generators.native_entry as native_entry_mod;
    importlib.reload(native_entry_mod);
    script = native_entry_mod.build_native_entry_script("main");

    forbidden = [
        "react-dom",
        "createRoot",
        "document.getElementById",
        "react-router",
        "BrowserRouter"
    ];
    for needle in forbidden {
        assert needle not in script , (
            f"native entry leaked web-only symbol: {needle!r}"
        );
    }
}

test "client config supports target-scoped npm table for react native" {
    import tempfile;
    import from jac_client.plugin.src.config_loader { JacClientConfig }

    with tempfile.TemporaryDirectory() as tmp {
        project_dir = Path(tmp);
        jac_toml = (
            "[project]\n"
            "name = \"rn-target-deps\"\n"
            "version = \"1.0.0\"\n"
            "entry-point = \"main.jac\"\n\n"
            "[dependencies.npm]\n"
            "react = \"^18.2.0\"\n\n"
            "[dependencies.npm.react_native]\n"
            "react-native = \"0.76.6\"\n"
            "\"expo-secure-store\" = \"~14.0.1\"\n\n"
            "[plugins.client]\n"
            "target = \"react_native\"\n"
        );
        (project_dir / "jac.toml").write_text(jac_toml, encoding="utf-8");
        cfg = JacClientConfig(project_dir=project_dir).load();
        deps = cfg["package"]["dependencies"];
        assert "react" in deps;
        assert deps["react-native"] == "0.76.6";
        assert deps["expo-secure-store"] == "~14.0.1";
    }
}

test "phase 3 dual-target gate can run e2e builds when explicitly enabled" {
    import shutil;
    import subprocess;
    import tempfile;
    import from test_helpers { get_env_with_npm, get_jac_command }

    if os.environ.get("JAC_PHASE3_DUAL_TARGET_GATE", "0") != "1" {
        pytest.skip(
            "Set JAC_PHASE3_DUAL_TARGET_GATE=1 to run emulator-grade dual-target gate."
        );
    }

    fixture_src = Path(__file__).parent / "fixtures" / "react_native_multiscreen";
    if not fixture_src.exists() {
        pytest.skip("react_native_multiscreen fixture not found");
    }

    with tempfile.TemporaryDirectory() as tmp {
        project_dir = Path(tmp) / "react_native_multiscreen";
        shutil.copytree(fixture_src, project_dir);
        env = get_env_with_npm();
        env["JAC_CLIENT_TARGET"] = "react_native";
        jac_cmd = get_jac_command();
        web_cmd = jac_cmd + ["build", "main.jac", "--client", "web"];
        web_result = subprocess.run(
            web_cmd,
            cwd=project_dir,
            env=env,
            capture_output=True,
            text=True,
            timeout=1200
        );
        assert web_result.returncode == 0 , (
            f"web build failed\nSTDOUT:\n{web_result.stdout}\nSTDERR:\n{web_result.stderr}"
        );
        rn_cmd = jac_cmd + [
            "build",
            "main.jac",
            "--client",
            "react-native",
            "--platform",
            "android"
        ];
        rn_result = subprocess.run(
            rn_cmd,
            cwd=project_dir,
            env=env,
            capture_output=True,
            text=True,
            timeout=3600
        );
        assert rn_result.returncode == 0 , (
            "react-native android build failed\n"
            f"STDOUT:\n{rn_result.stdout}\nSTDERR:\n{rn_result.stderr}"
        );
    }
}
