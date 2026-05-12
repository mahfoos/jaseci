"""Dev-server helpers for MobileTarget.

Handles local IP detection, backend server startup, Vite dev server
startup, and dev-config.json generation.
"""
import from pathlib { Path }
import from typing { Any }
import from jaclang.cli.console { console }
import subprocess;
import json;
import os;

# Single source of truth for the dev ports.  The generated WebView screen
# (setup_helpers._generate_webview_screen) reads these out of dev-config.json
# rather than hardcoding them, so the dev backend and the WebView always agree.
glob MOBILE_DEV_API_PORT: int = 9000,
     MOBILE_VITE_PORT: int = 5173;

"""Return http://127.0.0.1:{port}."""
def _make_localhost_url(port: int) -> str {
    return f"http://127.0.0.1:{port}";
}

"""Read api.base_url from jac.toml via JacClientConfig."""
def _get_toml_api_base_url(project_dir: Path) -> str {
    import from jac_client.plugin.src.config_loader { JacClientConfig }
    config_loader = JacClientConfig(project_dir);
    return config_loader.get_api_config().get('base_url', '');
}

"""Get the LAN IP a mobile device on the same network would use to reach this host.

Primary method: open a UDP socket and `connect()` it toward a public address.
UDP connect sends no packets — it just makes the kernel pick the source IP it
would route from, which is the routable LAN address.  Falls back to hostname
resolution (which on Ubuntu/Debian often returns 127.0.1.1, hence not primary),
then to loopback as a last resort.
"""
def _get_local_ip -> str {
    import socket;

    # Method 1: UDP-connect trick — no traffic, just resolves the source IP.
    try {
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM);
        try {
            s.connect(("8.8.8.8", 80));
            ip = str(s.getsockname()[0]);
        } finally {
            s.close();
        }
        if ip and not ip.startswith("127.") {
            return ip;
        }
    } except Exception { }

    # Method 2: hostname resolution (works offline; may yield 127.0.1.1).
    try {
        hostname = socket.gethostname();
        for info in socket.getaddrinfo(hostname, None, socket.AF_INET) {
            ip = str(info[4][0]);
            if not ip.startswith("127.") {
                return ip;
            }
        }
        (_h, _aliases, addr_list) = socket.gethostbyname_ex(hostname);
        for ip in addr_list {
            if not str(ip).startswith("127.") {
                return str(ip);
            }
        }
    } except Exception { }

    # Last resort: only loopback found — a phone can't reach this, but it's
    # the best we can report.
    return "127.0.0.1";
}

"""Resolve the production API URL: env var JAC_MOBILE_API_URL wins, else jac.toml [mobile.features].api_url, else ''."""
def _resolve_production_api_url(project_dir: Path) -> str {
    env_url = os.environ.get("JAC_MOBILE_API_URL", "").strip();
    if env_url {
        return env_url;
    }
    import from jac_client.plugin.src.mobile_config { MobileConfig }
    try {
        mobile_config = MobileConfig(project_dir=project_dir);
        config_data = mobile_config.load();
        return config_data.get('features', {}).get('api_url', '') or '';
    } except Exception {
        return '';
    }
}

"""Write dev-config.json with local IP, dev ports, and production API URL.

`api_port` is the port the local `jac start` backend listens on; the WebView
reads it (and `vitePort`) from this file so dev mode is self-consistent even
when the caller overrides the port.
"""
def _write_dev_config(
    mobile_dir: Path,
    project_dir: Path,
    local_ip: str,
    api_port: int = MOBILE_DEV_API_PORT
) {
    production_api_url = _resolve_production_api_url(project_dir);

    dev_config = {
        'localIP': local_ip,
        'devApiPort': api_port,
        'vitePort': MOBILE_VITE_PORT,
        'productionApiUrl': production_api_url
    };

    dev_config_path = mobile_dir / "dev-config.json";
    with open(dev_config_path, "w") as f {
        json.dump(dev_config, f, indent=2);
    }
    console.print(
        f"  ✔ Dev config written (IP: {local_ip}, API port: {api_port})",
        style="success"
    );
}

"""Write dev-config.json for a release build — only productionApiUrl matters."""
def _write_build_config(mobile_dir: Path, project_dir: Path) {
    production_api_url = _resolve_production_api_url(project_dir);

    if not production_api_url {
        console.warning(
            "  No backend URL configured.  Set [mobile.features].api_url in jac.toml " + "or pass JAC_MOBILE_API_URL=... — the APK will ship with an empty " + "API URL and runtime calls will fail."
        );
    } else {
        source = "env JAC_MOBILE_API_URL"
            if os.environ.get("JAC_MOBILE_API_URL", "").strip()
            else "jac.toml [mobile.features].api_url";
        console.print(
            f"  Baking productionApiUrl = {production_api_url} (from {source})",
            style="muted"
        );
    }

    build_config = {'localIP': '', 'productionApiUrl': production_api_url};

    config_path = mobile_dir / "dev-config.json";
    with open(config_path, "w") as f {
        json.dump(build_config, f, indent=2);
    }
    console.print(f"  ✔ Build config written", style="success");
}

"""Start Vite dev server for HMR support."""
def _start_vite_dev_server(
    entry_file: Path, project_dir: Path, api_port: int
) -> subprocess.Popen {
    import from jac_client.plugin.src.vite_bundler { ViteBundler }

    try {
        bundler = ViteBundler(
            project_dir=project_dir, output_dir=None, minify=False, config_path=None
        );
        dev_config_path = bundler.create_vite_config(
            entry_file,
            api_base_url_override=f"http://localhost:{api_port}",
            is_dev=True,
            api_port=api_port
        );
        process = bundler.start_dev_server(
            port=MOBILE_VITE_PORT, suppress_initial_output=True
        );
        return process;
    } except Exception as e {
        raise RuntimeError(f"Failed to start Vite dev server: {e}");
    }
}

"""Start the Jac API server in the background.

"""
def _start_backend_server(
    entry_file: Path, project_dir: Path, port: int
) -> subprocess.Popen {
    verbose = os.environ.get("JAC_MOBILE_VERBOSE_BACKEND", "").strip() == "1";
    stdout_pipe = None if verbose else subprocess.DEVNULL;
    stderr_pipe = None if verbose else subprocess.DEVNULL;
    try {
        process = subprocess.Popen(
            ["jac", "start", str(entry_file), "--port", str(port)],
            cwd=str(project_dir),
            stdout=stdout_pipe,
            stderr=stderr_pipe
        );
        return process;
    } except Exception as e {
        raise RuntimeError(f"Failed to start backend server: {e}");
    }
}
