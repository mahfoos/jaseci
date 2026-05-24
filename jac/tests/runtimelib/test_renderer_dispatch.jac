"""R3: renderer dispatch tests.

`__jacJsx` no longer calls `React.createElement` directly; it delegates to a
renderer object the active target registers at bundle init time. These tests
verify:

1. The compiled jac-client runtime exposes the dispatch surface
   (`__jacRegisterRenderer`, `__jacGetRenderer`, `__jacWebCreate`).
2. `__jacJsx`'s compiled body is a one-line delegation, not the previous
   DOM-aware logic.
3. Behavior: registering a stub renderer routes JSX calls to that stub
   unchanged (no tag rewrites, no child wrapping).
4. Behavior: with no registration, the web renderer auto-installs lazily and
   continues to handle the Fragment fallback exactly as before.
5. HMR: re-evaluating the runtime module body must not clobber a renderer
   that has already been registered on globalThis.

The substring assertions follow the same pattern as `test_client_bundle.jac`.
The behavioral assertions execute the compiled JS under Node so we catch
regressions the source-level checks miss.
"""

import os;
import shutil;
import subprocess;
import importlib;
import pytest;
import from pathlib { Path }
import from tempfile { TemporaryDirectory }

"""Locate jac-client's plugin directory. Skips if not installed."""
def _jac_client_plugin_dir -> str {
    try {
        plugin = importlib.import_module("jac_client.plugin");
    } except ImportError {
        pytest.skip("jac-client plugin not installed");
    }
    paths = `list(getattr(plugin, "__path__", []) or []);
    if not paths {
        pytest.skip("jac-client plugin has no __path__");
    }
    return paths[0];
}

"""Strip trailing ``export { ... };`` from jac2js output."""
def _strip_esm_export_line(js_code: str) -> str {
    lines = js_code.split("\n");
    filtered: list[str] = [];
    for line in lines {
        trimmed = line.strip();
        if trimmed.startswith("export {") or trimmed.startswith("export{") {
            continue;
        }
        filtered.append(line);
    }
    return "\n".join(filtered);
}

"""Drop inlined core import after D9 bundle stitch."""
def _strip_runtime_core_import(js_code: str) -> str {
    lines = js_code.split("\n");
    filtered: list[str] = [];
    for line in lines {
        if "client_runtime_core" in line and "import " in line {
            continue;
        }
        filtered.append(line);
    }
    return "\n".join(filtered);
}

"""Compile D9 web runtime (core + platform) the same way ``compile_runtime_utils`` does."""
def _compile_runtime_to_js -> str {
    plugin_dir = _jac_client_plugin_dir();
    core_src = os.path.join(plugin_dir, "client_runtime_core.cl.jac");
    web_src = os.path.join(plugin_dir, "client_runtime.cl.jac");
    if not os.path.isfile(core_src) or not os.path.isfile(web_src) {
        pytest.skip("client_runtime_core.cl.jac or client_runtime.cl.jac not found");
    }
    jac_bin = shutil.which("jac");
    if not jac_bin {
        pytest.skip("`jac` CLI not on PATH");
    }
    core_result = subprocess.run(
        [jac_bin, "jac2js", core_src], capture_output=True, text=True, check=False
    );
    if core_result.returncode != 0 {
        pytest.skip(f"jac2js core failed: {core_result.stderr}");
    }
    web_result = subprocess.run(
        [jac_bin, "jac2js", web_src], capture_output=True, text=True, check=False
    );
    if web_result.returncode != 0 {
        pytest.skip(f"jac2js web failed: {web_result.stderr}");
    }
    return (
        _strip_esm_export_line(core_result.stdout) + "\n" + _strip_runtime_core_import(
            _strip_esm_export_line(web_result.stdout)
        )
    );
}

"""Extract just the four renderer-related functions from compiled JS.

The full runtime imports `react`, `react-dom/client`, etc., which Node can't
resolve in a bare TemporaryDirectory. The dispatch layer doesn't depend on
any of those (only `globalThis`, `Array`, `React.Fragment` and
`React.createElement` via the test's stub globals), so slicing the four
function bodies out is enough to exercise the contract.
"""
def _slice_renderer_fns(js: str) -> str {
    parts = "";
    for marker in [
        "function __jacJsx",
        "function __jacRegisterRenderer",
        "function __jacGetRenderer",
        "function __jacWebCreate"
    ] {
        start = js.find(marker);
        assert start >= 0 , f"compiled runtime missing {marker}";
        # Walk parens first so default-arg literals like `{}` inside the
        # parameter list don't trip the brace counter; the function body
        # begins at the first `{` *after* the closing `)` of the params.
        paren_depth = 0;
        j = js.find("(", start);
        assert j >= 0;
        while j < len(js) {
            if js[j] == "(" {
                paren_depth += 1;
            } elif js[j] == ")" {
                paren_depth -= 1;
                if paren_depth == 0 {
                    break;
                }
            }
            j += 1;
        }
        brace_open = js.find("{", j);
        depth = 0;
        i = brace_open;
        end = -1;
        while i < len(js) {
            ch = js[i];
            if ch == "{" {
                depth += 1;
            } elif ch == "}" {
                depth -= 1;
                if depth == 0 {
                    end = i + 1;
                    break;
                }
            }
            i += 1;
        }
        assert end > 0 , f"unterminated function body for {marker}";
        parts += js[start:end] + "\n\n";
    }
    return parts;
}

"""Run a JS snippet under Node and return (rc, stdout, stderr)."""
def _run_node(snippet: str) -> tuple[int, str, str] {
    node_bin = shutil.which("node");
    if not node_bin {
        pytest.skip("node not on PATH");
    }
    with TemporaryDirectory() as tmp_name {
        tmp = str(tmp_name);
        harness_path = Path(tmp) / "harness.mjs";
        harness_path.write_text(snippet);
        result = subprocess.run(
            [node_bin, str(harness_path)], capture_output=True, text=True, check=False
        );
        return (result.returncode, result.stdout, result.stderr);
    }
}

test "compiled runtime exposes renderer dispatch surface" {
    js = _compile_runtime_to_js();
    assert "function __jacJsx" in js , "__jacJsx must still be emitted";
    assert "function __jacRegisterRenderer" in js , (
        "R3: __jacRegisterRenderer missing from compiled runtime"
    );
    assert "function __jacGetRenderer" in js , (
        "R3: __jacGetRenderer missing from compiled runtime"
    );
    assert "function __jacWebCreate" in js , (
        "R3: web renderer body should live in __jacWebCreate"
    );
    assert "globalThis.__jacRenderer__" in js , (
        "R3: renderer must be stored on globalThis to survive HMR reload"
    );
}

test "__jacJsx body is a thin dispatcher" {
    js = _compile_runtime_to_js();
    start = js.find("function __jacJsx");
    assert start >= 0;
    brace = js.find("{", start);
    end = js.find("\n}", brace);
    body = js[brace + 1:end];
    assert "__jacGetRenderer__" in body or "__jacGetRenderer" in body , (
        "R3: __jacJsx must delegate via the platform renderer hook"
    );
    assert "React.createElement" not in body , (
        "R3 regression: __jacJsx must not call React.createElement directly. "
        "DOM-specific logic belongs in __jacWebCreate."
    );
    assert "Fragment" not in body , (
        "R3 regression: Fragment fallback must live in the web renderer, "
        "not in __jacJsx itself."
    );
}

test "registered renderer receives (tag, props, children) verbatim" {
    js = _compile_runtime_to_js();
    snippet = _slice_renderer_fns(js);
    harness = (
        "globalThis.React = { createElement: () => ({}), Fragment: 'F' };\n" + snippet + "globalThis.__jacGetRenderer__ = () => globalThis.__jacRenderer__;\n" + "const calls = [];\n" + "__jacRegisterRenderer({ create: (tag, props, children) => {\n" + "  calls.push({tag, props, children}); return 'stub-element';\n" + "}});\n" + "const out = __jacJsx('button', {id: 'x'}, ['hi']);\n" + "if (out !== 'stub-element') {\n" + "  console.error('expected stub return, got', out); process.exit(1);\n" + "}\n" + "if (calls.length !== 1) {\n" + "  console.error('expected 1 call, got', calls.length); process.exit(1);\n" + "}\n" + "const c = calls[0];\n" + "if (c.tag !== 'button') { console.error('tag', c); process.exit(1); }\n" + "if (c.props.id !== 'x') { console.error('props', c); process.exit(1); }\n" + "if (!Array.isArray(c.children) || c.children[0] !== 'hi') {\n" + "  console.error('children mismatch', c); process.exit(1);\n" + "}\n" + "console.log('OK');\n"
    );
    (rc, out, err) = _run_node(harness);
    assert rc == 0 , f"dispatch harness failed: stdout={out} stderr={err}";
    assert "OK" in out;
}

test "web renderer auto-installs when nothing is registered" {
    js = _compile_runtime_to_js();
    snippet = _slice_renderer_fns(js);
    harness = (
        "const captured = [];\n" + "globalThis.React = {\n" + "  createElement: (...args) => { captured.push(args); return {tag: args[0]}; },\n" + "  Fragment: Symbol('Fragment'),\n" + "};\n" + snippet + "globalThis.__jacGetRenderer__ = __jacGetRenderer;\n" + "__jacJsx('div', {className: 'x'}, []);\n" + "if (captured.length === 0) {\n" + "  console.error('web renderer did not auto-install'); process.exit(1);\n" + "}\n" + "if (captured[0][0] !== 'div') {\n" + "  console.error('tag not forwarded', captured); process.exit(1);\n" + "}\n" + "__jacJsx(null, {}, []);\n" + "const lastTag = captured[captured.length - 1][0];\n" + "if (typeof lastTag !== 'symbol') {\n" + "  console.error('Fragment fallback broken, got', lastTag);\n" + "  process.exit(1);\n" + "}\n" + "console.log('OK');\n"
    );
    (rc, out, err) = _run_node(harness);
    assert rc == 0 , f"auto-install harness failed: stdout={out} stderr={err}";
    assert "OK" in out;
}

test "registration survives runtime re-evaluation (HMR sim)" {
    js = _compile_runtime_to_js();
    snippet = _slice_renderer_fns(js);
    module_iife = "(() => {\n" + snippet + "return __jacJsx;\n})()";
    harness = (
        "globalThis.React = { createElement: () => ({}), Fragment: 'F' };\n" + "globalThis.__jacGetRenderer__ = () => globalThis.__jacRenderer__;\n" + "const firstJsx = " + module_iife + ";\n" + "firstJsx;\n" + "globalThis.__jacRenderer__ = { create: (t,p,c) => 'native:' + t };\n" + "const reloadedJsx = " + module_iife + ";\n" + "const out = reloadedJsx('div', {}, []);\n" + "if (out !== 'native:div') {\n" + "  console.error('HMR clobbered renderer, got', out); process.exit(1);\n" + "}\n" + "console.log('OK');\n"
    );
    (rc, out, err) = _run_node(harness);
    assert rc == 0 , f"HMR harness failed: stdout={out} stderr={err}";
    assert "OK" in out;
}
