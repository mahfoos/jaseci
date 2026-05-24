"""React Native build target.

Skeleton for the Phase 1 `react-native` target from
`REACT_NATIVE_ARCHITECTURE.md`. Unlike `MobileTarget`, this target does **not**
extend `WebTarget` (D3): Metro replaces Vite end-to-end, so inheriting the
web bundle pipeline would couple us to internals we explicitly need to
diverge from.

Today this class registers itself with the target registry so
``jac build --client react-native`` and ``jac setup react-native`` resolve to
a meaningful object. Each lifecycle method raises ``NotImplementedError``
with a pointer to the architecture doc — subsequent Phase 1 PRs fill them in
(Expo scaffold, Metro invocation, native runtime wiring, native entry
generator, etc.). The clear failure mode is intentional: silent partial
behavior would be worse than an obvious "not yet" while the scaffold is
being assembled.
"""
import from pathlib { Path }
import from typing { Optional }
import from jaclang.runtimelib.watcher { FileChangeEvent }
import from jac_client.plugin.src.targets.registry { ClientTarget }

# Importing this module is the documented way to trigger registration of the
# 'native' entry generator with `jaclang.runtimelib.entry_generators`. The
# target class doesn't call into it yet — the import side-effect keeps the
# registration story consistent with `web_entry.jac` for when the build flow
# lands.
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

    """Start the Metro dev loop with Fast Refresh (Phase 2 — not yet)."""
    override def dev(
        entry_file: Path, project_dir: Path, port: int = 8000, api_port: int = 0
    ) -> None;

    """Build then launch on a connected device or emulator (Phase 2+)."""
    override def start(
        entry_file: Path, project_dir: Path, api_port: int = 8000
    ) -> None;
}
