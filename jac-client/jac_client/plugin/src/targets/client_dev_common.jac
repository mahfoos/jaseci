"""Shared helpers for mobile/react-native dev loops."""

import shutil;
import socket;
import subprocess;
import from pathlib { Path }
import from typing { Optional }
import from jaclang.cli.console { console }

"""Return a bind error string for a TCP port, or None if bind succeeds."""
def port_bind_error(port: int) -> Optional[str] {
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM);
    try {
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1);
        s.bind(("0.0.0.0", port));
        return None;
    } except OSError as e {
        return str(e);
    } finally {
        s.close();
    }
}

"""Fail fast when a dev port is already bound."""
def assert_port_available(port: int, role: str, failure_hint: str) -> None {
    err = port_bind_error(port);
    if err is None {
        return;
    }
    raise RuntimeError(f"{role} port {port} is already in use ({err}). {failure_hint}");
}

"""Find a bindable port, scanning upward from ``start_port``."""
def resolve_port_or_next_available(
    start_port: int,
    role: str,
    reserved: Optional[list[int]] = None,
    max_scan: int = 200
) -> int {
    reserved_set: set[int] = set(reserved or []);
    candidate = start_port;
    first_err: Optional[str] = None;
    scans = 0;

    while scans <= max_scan {
        if candidate in reserved_set {
            candidate += 1;
            scans += 1;
            continue;
        }
        err = port_bind_error(candidate);
        if err is None {
            if candidate != start_port {
                if first_err is None {
                    console.warning(
                        f"  {role} port {start_port} is reserved; using {candidate}."
                    );
                } else {
                    console.warning(
                        f"  {role} port {start_port} is in use ({first_err}); "
                        f"using {candidate}."
                    );
                }
            }
            return candidate;
        }
        if first_err is None {
            first_err = err;
        }
        candidate += 1;
        scans += 1;
    }

    raise RuntimeError(
        f"Unable to find a free {role} port starting at {start_port} "
        f"(scanned {max_scan + 1} ports)."
    );
}

"""Best-effort adb reverse for the provided port list."""
def setup_android_port_reverse_common(ports: list[int], timeout: int = 5) -> None {
    if not shutil.which("adb") {
        return;
    }
    seen: set[int] = set();
    for port in ports {
        if port <= 0 or port in seen {
            continue;
        }
        seen.add(port);
        cmd = ["adb", "reverse", f"tcp:{port}", f"tcp:{port}"];
        try {
            result = subprocess.run(
                cmd, capture_output=True, text=True, timeout=timeout, check=False
            );
            if result.returncode == 0 {
                console.print(
                    f"  ✔ adb reverse tcp:{port} tcp:{port}", style="success"
                );
            } else {
                err = (result.stderr or "").strip() or "unknown adb error";
                console.warning(f"  ⚠ adb reverse failed for tcp:{port} ({err})");
            }
        } except Exception as e {
            console.warning(f"  ⚠ adb reverse failed for tcp:{port} ({e})");
        }
    }
}

"""Return True if watchdog is importable, else warn once with target-specific text."""
def ensure_watchdog_common(target_name: str) -> bool {
    try {
        import watchdog;
        return True;
    } except ImportError {
        console.warning(
            f"  watchdog not installed — saving .jac files will not refresh {target_name}. "
            "Install with: pip install 'watchdog>=3.0.0' (or add to [dev-dependencies]).",
            style="muted"
        );
        return False;
    }
}

"""Spawn ``jaclang start --no_client`` for local API dev."""
def start_backend_server_common(entry_file: Path, project_dir: Path, port: int) -> any {
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
