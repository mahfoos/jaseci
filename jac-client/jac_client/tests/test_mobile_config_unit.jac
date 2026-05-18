"""Unit tests for MobileConfig.

1. get_app_json_config() produces a structurally valid Expo config from a
   synthetic [mobile] TOML table.
2. _is_valid_bundle_id / _generate_bundle_id round-trip.
3. _resolve_production_api_url: env var wins over TOML, TOML wins over empty.
"""

import os;
import tempfile;
import from pathlib { Path }

import from jac_client.plugin.src.impl.mobile_config {
    _generate_bundle_id,
    _is_valid_bundle_id
}

glob _MINIMAL_JAC_TOML = """[project]
name = "test-app"
version = "1.0.0"

[mobile]
name = "test-app"
bundle_id = "com.example.testapp"
version = "1.2.3"
display_name = "Test App"
slug = "test-app"
scheme = "testapp"

[mobile.platforms]
ios = true
android = true

[mobile.features]
use_sidecar = false
api_url = "https://toml.example.com"

[mobile.expo]
orientation = "portrait"
userInterfaceStyle = "light"
icon = "./assets/icon.png"
plugins = ["expo-router", "expo-dev-client"]
""";


# =============================================================================
# 1. get_app_json_config() produces a valid Expo config
# =============================================================================
test "get_app_json_config produces valid expo config structure" {
    import from jac_client.plugin.src.mobile_config { MobileConfig }

    with tempfile.TemporaryDirectory() as tmp {
        project_dir = Path(tmp);
        (project_dir / "jac.toml").write_text(_MINIMAL_JAC_TOML);

        old_cwd = os.getcwd();
        try {
            os.chdir(str(project_dir));
            cfg = MobileConfig(project_dir=project_dir);
            app_json = cfg.get_app_json_config();
        } finally {
            os.chdir(old_cwd);
        }

        assert "expo" in app_json , "app_json must have 'expo' key";
        expo = app_json["expo"];

        assert expo.get("name") == "Test App" , f"Expected 'Test App', got {expo.get('name')}";
        assert expo.get("slug") == "test-app" , f"Expected 'test-app', got {expo.get('slug')}";
        assert expo.get("version") == "1.2.3" , f"Expected '1.2.3', got {expo.get('version')}";

        assert expo.get("ios", {}).get("bundleIdentifier") == "com.example.testapp";
        assert expo.get("android", {}).get("package") == "com.example.testapp";

        plugins = expo.get("plugins", []);
        assert "expo-router" in plugins , "expo-router must be in plugins";
        assert "expo-dev-client" in plugins , "expo-dev-client must be in plugins";
    }
}


# =============================================================================
# 2. _generate_bundle_id / _is_valid_bundle_id round-trip
# =============================================================================
test "generate_bundle_id produces a valid bundle id" {
    generated = _generate_bundle_id("My Jac App");
    assert _is_valid_bundle_id(generated) , (
        f"_generate_bundle_id produced invalid id: {generated}"
    );
    assert generated.startswith("com.example.") , (
        f"Expected 'com.example.*' prefix, got: {generated}"
    );
}

test "generate_bundle_id handles spaces hyphens underscores" {
    for name in ["hello world", "hello-world", "hello_world", "HelloWorld"] {
        bid = _generate_bundle_id(name);
        assert _is_valid_bundle_id(bid) , (
            f"_generate_bundle_id('{name}') = '{bid}' is not valid"
        );
    }
}

test "is_valid_bundle_id accepts well-formed identifiers" {
    valid_ids = [
        "com.example.app",
        "com.example.myapp",
        "org.myorg.myapp",
        "io.github.user.app"
    ];
    for bid in valid_ids {
        assert _is_valid_bundle_id(bid) , f"Should be valid: {bid}";
    }
}

test "is_valid_bundle_id rejects malformed identifiers" {
    invalid_ids = [
        "singlepart",
        "com.example.my-app",
        "com.example.123app",
        ""
    ];
    for bid in invalid_ids {
        assert not _is_valid_bundle_id(bid) , f"Should be invalid: {bid}";
    }
}


# =============================================================================
# 3. _resolve_production_api_url precedence: env > toml > empty
# =============================================================================
test "_resolve_production_api_url env var wins over toml" {
    import from jac_client.plugin.src.targets.mobile.dev_helpers {
        _resolve_production_api_url
    }

    with tempfile.TemporaryDirectory() as tmp {
        project_dir = Path(tmp);
        (project_dir / "jac.toml").write_text(_MINIMAL_JAC_TOML);

        saved = os.environ.get("JAC_MOBILE_API_URL");
        try {
            os.environ["JAC_MOBILE_API_URL"] = "https://env.example.com";
            # env var is checked before loading TOML, so no chdir needed
            result = _resolve_production_api_url(project_dir);
            assert result == "https://env.example.com" , (
                f"Env var should win over TOML; got: {result}"
            );
        } finally {
            if saved is None {
                if "JAC_MOBILE_API_URL" in os.environ {
                    del os.environ["JAC_MOBILE_API_URL"];
                }
            } else {
                os.environ["JAC_MOBILE_API_URL"] = saved;
            }
        }
    }
}

test "_resolve_production_api_url toml wins when env not set" {
    import from jac_client.plugin.src.targets.mobile.dev_helpers {
        _resolve_production_api_url
    }

    with tempfile.TemporaryDirectory() as tmp {
        project_dir = Path(tmp);
        (project_dir / "jac.toml").write_text(_MINIMAL_JAC_TOML);

        saved = os.environ.pop("JAC_MOBILE_API_URL", None);
        old_cwd = os.getcwd();
        try {
            os.chdir(str(project_dir));
            result = _resolve_production_api_url(project_dir);
            assert result == "https://toml.example.com" , (
                f"TOML api_url should be used; got: {result}"
            );
        } finally {
            os.chdir(old_cwd);
            if saved is not None {
                os.environ["JAC_MOBILE_API_URL"] = saved;
            }
        }
    }
}

test "_resolve_production_api_url empty when neither env nor toml set" {
    import from jac_client.plugin.src.targets.mobile.dev_helpers {
        _resolve_production_api_url
    }

    toml_empty_api = """[project]
name = "test-app"
version = "1.0.0"

[mobile]
name = "test-app"
bundle_id = "com.example.testapp"
version = "1.0.0"
display_name = "Test App"

[mobile.features]
use_sidecar = false
api_url = ""
""";

    with tempfile.TemporaryDirectory() as tmp {
        project_dir = Path(tmp);
        (project_dir / "jac.toml").write_text(toml_empty_api);

        saved = os.environ.pop("JAC_MOBILE_API_URL", None);
        old_cwd = os.getcwd();
        try {
            os.chdir(str(project_dir));
            result = _resolve_production_api_url(project_dir);
            assert result == "" , f"Should return empty string; got: '{result}'";
        } finally {
            os.chdir(old_cwd);
            if saved is not None {
                os.environ["JAC_MOBILE_API_URL"] = saved;
            }
        }
    }
}
