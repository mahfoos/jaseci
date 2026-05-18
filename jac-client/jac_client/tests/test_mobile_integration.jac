"""Integration tests for jac setup mobile — full scaffold pipeline.

Exercises the real `jac setup mobile` CLI command end-to-end:
  1. Scaffold generation in a temp project
  2. jac.toml [mobile] section is appended correctly
  3. Placeholder icons are generated
  4. Idempotency (running twice doesn't duplicate [mobile])
  5. all-in-one committed example has no pre-baked mobile config
  6. all-in-one .gitignore excludes mobile/
"""

import os;
import subprocess;
import tempfile;
import tomllib;
import from pathlib { Path }

import from test_helpers { get_jac_command }

glob _tests_dir = Path(os.path.dirname(__file__)),
     _jac_client_root = _tests_dir.parent,
     _all_in_one_path = _jac_client_root / "examples" / "all-in-one",
     _MINIMAL_JAC_TOML = (
         "[project]\n"
         "name = \"test-mobile-app\"\n"
         "version = \"1.0.0\"\n"
         "description = \"Minimal jac project for mobile integration tests\"\n"
         "entry-point = \"main.jac\"\n"
     ),
     _MINIMAL_MAIN_JAC = (
         "walker test_walker {\n"
         "    can greet with `root entry {\n"
         "        print(\"hello\");\n"
         "    }\n"
         "}\n"
     );


test "jac setup mobile scaffolds mobile directory structure" {
    with tempfile.TemporaryDirectory() as tmp {
        project_dir = Path(tmp);
        (project_dir / "jac.toml").write_text(_MINIMAL_JAC_TOML);
        (project_dir / "main.jac").write_text(_MINIMAL_MAIN_JAC);
        jac_cmd = get_jac_command();
        result = subprocess.run(
            [*jac_cmd, "setup", "mobile"],
            cwd=str(project_dir),
            capture_output=True,
            text=True,
            timeout=60
        );
        print(f"[DEBUG] stdout:\n{result.stdout}");
        print(f"[DEBUG] stderr:\n{result.stderr}");
        assert result.returncode == 0 , (
            f"jac setup mobile failed (rc={result.returncode}):\n{result.stderr}"
        );
        mobile_dir = project_dir / "mobile";
        assert mobile_dir.is_dir() , "mobile/ directory not created";
        for expected in [
            mobile_dir / "app.json",
            mobile_dir / "package.json",
            mobile_dir / "tsconfig.json",
            mobile_dir / "app" / "index.tsx",
            mobile_dir / "app" / "_layout.tsx",
            mobile_dir / "assets" / "jac-app" / "create-bundle.js",
            mobile_dir / ".gitignore",

        ] {
            assert expected.exists() , f"expected file missing: {expected.name}";
        }
    }
}


test "jac setup mobile generates placeholder icon files" {
    with tempfile.TemporaryDirectory() as tmp {
        project_dir = Path(tmp);
        (project_dir / "jac.toml").write_text(_MINIMAL_JAC_TOML);
        (project_dir / "main.jac").write_text(_MINIMAL_MAIN_JAC);
        jac_cmd = get_jac_command();
        result = subprocess.run(
            [*jac_cmd, "setup", "mobile"],
            cwd=str(project_dir),
            capture_output=True,
            text=True,
            timeout=60
        );
        assert result.returncode == 0 , f"jac setup mobile failed:\n{result.stderr}";
        assets_dir = project_dir / "mobile" / "assets";
        for icon in ["icon.png", "splash.png", "adaptive-icon.png", "favicon.png"] {
            assert (assets_dir / icon).exists() , f"placeholder icon missing: {icon}";
            assert (assets_dir / icon).stat().st_size > 0 , f"icon is empty: {icon}";
        }
    }
}


test "jac setup mobile appends [mobile] section to jac.toml" {
    with tempfile.TemporaryDirectory() as tmp {
        project_dir = Path(tmp);
        toml_path = project_dir / "jac.toml";
        toml_path.write_text(_MINIMAL_JAC_TOML);
        (project_dir / "main.jac").write_text(_MINIMAL_MAIN_JAC);
        with open(str(toml_path), "rb") as f {
            before = tomllib.load(f);
        }
        assert "mobile" not in before , "[mobile] must not exist before setup";
        jac_cmd = get_jac_command();
        result = subprocess.run(
            [*jac_cmd, "setup", "mobile"],
            cwd=str(project_dir),
            capture_output=True,
            text=True,
            timeout=60
        );
        assert result.returncode == 0 , f"jac setup mobile failed:\n{result.stderr}";
        with open(str(toml_path), "rb") as f {
            after = tomllib.load(f);
        }
        assert "mobile" in after , "[mobile] section not added to jac.toml";
        mobile = after["mobile"];
        assert "name" in mobile , "[mobile].name missing";
        assert "bundle_id" in mobile , "[mobile].bundle_id missing";
        assert "platforms" in mobile , "[mobile.platforms] missing";
        assert "features" in mobile , "[mobile.features] missing";
        assert "api_url" in mobile["features"] , "[mobile.features].api_url missing";
        assert "expo" in mobile , "[mobile.expo] missing";
    }
}


test "jac setup mobile is idempotent — [mobile] not duplicated on second run" {
    with tempfile.TemporaryDirectory() as tmp {
        project_dir = Path(tmp);
        (project_dir / "jac.toml").write_text(_MINIMAL_JAC_TOML);
        (project_dir / "main.jac").write_text(_MINIMAL_MAIN_JAC);
        jac_cmd = get_jac_command();
        for _ in range(2) {
            result = subprocess.run(
                [*jac_cmd, "setup", "mobile"],
                cwd=str(project_dir),
                capture_output=True,
                text=True,
                timeout=60
            );
            assert result.returncode == 0 , (
                f"jac setup mobile failed on repeat run:\n{result.stderr}"
            );
        }
        content = (project_dir / "jac.toml").read_text();
        mobile_count = content.count("[mobile]");
        assert mobile_count == 1 , (
            f"[mobile] duplicated after second run ({mobile_count} occurrences)"
        );
    }
}


test "all-in-one jac.toml has no pre-committed [mobile] section" {
    toml_path = _all_in_one_path / "jac.toml";
    assert toml_path.exists() , "all-in-one jac.toml not found";

    with open(str(toml_path), "rb") as f {
        config = tomllib.load(f);
    }
    assert "mobile" not in config , (
        "all-in-one jac.toml must not pre-commit [mobile] — "
        "generated by `jac setup mobile`"
    );
    envs = config.get("environments", {});
    assert "mobile" not in envs , (
        "all-in-one jac.toml must not pre-commit [environments.mobile.*]"
    );
}


test "all-in-one .gitignore excludes mobile/" {
    gitignore_path = _all_in_one_path / ".gitignore";
    assert gitignore_path.exists() , "all-in-one .gitignore not found";

    lines = gitignore_path.read_text().splitlines();
    assert "mobile/" in lines , (
        "all-in-one .gitignore must contain 'mobile/' — "
        "scaffold is generated by `jac setup mobile` and must not be committed"
    );
}
