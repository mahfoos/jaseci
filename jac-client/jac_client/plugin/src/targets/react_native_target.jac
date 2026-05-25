"""React Native build target.

Implements the Expo + Metro + native-runtime path for
``--client react-native``. Unlike ``MobileTarget``, this target does **not**
extend ``WebTarget`` (D3): Metro replaces Vite end-to-end, so inheriting the
web bundle pipeline would couple us to internals we explicitly need to
diverge from.
"""
import from pathlib { Path }
import from typing { Optional }
import from jaclang.runtimelib.watcher { FileChangeEvent }
import from jac_client.plugin.src.targets.registry { ClientTarget }

# Importing this module triggers side-effect registration of the "native"
# entry generator in `jaclang.runtimelib.entry_generators`.
import from jac_client.plugin.src.entry_generators.native_entry {
    build_native_entry_script
}

"""Binds JacClientCompiler state for JacFileWatcher (decl only; see impl).

Mirrors ``_MobileHmrHandler`` in ``mobile_target.jac`` — the watchdog
callback needs a stable ``on_event(evt)`` method, and Jac watchers expect
a callable, so we shape the closure as an object with bound state. Phase
2 (Fast Refresh) instantiates this from ``ReactNativeTarget.dev`` and
hands the bound ``on_event`` to ``JacFileWatcher.add_callback``.
"""
obj _RNHmrHandler {
    has compiler: any,
        entry_file: Path,
        project_dir: Path,
        rn_dir: Path,
        entry_module: str;

    def on_event(evt: FileChangeEvent) -> None;
}

"""React Native build target (Expo + Metro + Hermes + New Architecture).

The defaults mirror decisions D7/D8/D11 from the architecture doc:
  * Expo (not bare RN) — `requires_setup = True`, scaffold lives in
    ``mobile-rn/`` so it doesn't collide with the Capacitor ``android/`` and
    ``ios/`` directories (D11).
  * Production stack from day one: Hermes, New Architecture, secure-store
    (wired in later Phase 1 PRs).
  * Output directory is platform-specific Android debug output until iOS
    lands in Phase 4.
"""
obj ReactNativeTarget(ClientTarget) {
    has name: str = "react-native",
        default: bool = False,
        requires_setup: bool = True,
        config_section: str = "react_native",
        output_dir: Path = Path("mobile-rn/android/app/build/outputs");

    """Setup the Expo project scaffold under ``mobile-rn/``."""
    override def setup(project_dir: Path) -> None;

    """Build a debug APK (Phase 1) or release artifact (Phase 4)."""
    override def build(
        entry_file: Path, project_dir: Path, platform: Optional[str] = None
    ) -> Path;

    """Start the Metro dev loop with Fast Refresh."""
    override def dev(
        entry_file: Path, project_dir: Path, port: int = 8000, api_port: int = 0
    ) -> None;

    """Build then launch on a connected device or emulator (Phase 2+)."""
    override def start(
        entry_file: Path, project_dir: Path, api_port: int = 8000
    ) -> None;
}
