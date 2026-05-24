"""Platform-neutral Jac client compiler.

Owns everything that turns a Jac client entry module (and its dependency graph)
into a populated ``.jac/client/compiled/`` directory of plain JS modules plus a
runtime, routes manifest, and copied static assets. Knows nothing about Vite,
Metro, or any specific bundler — those live one layer up.
"""
import contextlib;
import from collections.abc { Callable }
import from pathlib { Path }
import from types { ModuleType }
import from typing { TYPE_CHECKING, Any }
import from jaclang.runtimelib.client_bundle { ClientBundleError }
import from .asset_processor { AssetProcessor }
import from .import_processor { ImportProcessor }
import from .jac_to_js { JacToJSCompiler }
import from .route_scanner { RouteScanner, RouteEntry }

with entry {
    if TYPE_CHECKING { }
}

"""Bundler-agnostic compiler that produces ``.jac/client/compiled/``."""
class JacClientCompiler {
    with entry {
        ROUTER_EXPORTS = [
            'Router',
            'Routes',
            'Route',
            'Link',
            'Navigate',
            'Outlet',
            'useNavigate',
            'useLocation',
            'useParams',
            'AuthGuard'
        ];
        COMPOUND_EXTENSIONS = ['.cl.jac', '.impl.jac', '.test.jac'];
    }

    def init(
        self: JacClientCompiler,
        project_dir: Path,
        runtime_path: (Path | None),
        compile_to_js_func: Callable[([Path], tuple[(str, (ModuleType | None))])],
        extract_exports_func: Callable[([any], list[str])],
        extract_globals_func: Callable[([any, ModuleType], dict[(str, Any)])],
        compiled_dir: (Path | None) = None
    );

    def _get_client_dir(self: JacClientCompiler) -> Path;
    def _jac_path_to_js(self: JacClientCompiler, rel_str: str) -> str;
    def compile_runtime_utils(self: JacClientCompiler) -> tuple[str, list[str]];
    def compile_pwa_runtime(self: JacClientCompiler) -> tuple[str, list[str]];
    def compile_dependencies_recursively(
        self: JacClientCompiler,
        module_path: Path,
        visited: (set[Path] | None) = None,
        collected_exports: (set[str] | None) = None,
        collected_globals: (dict[(str, Any)] | None) = None,
        source_root: (Path | None) = None
    ) -> None;

    def _copy_js_file(
        self: JacClientCompiler, js_path: Path, source_root: Path
    ) -> None;

    def _copy_ts_file(
        self: JacClientCompiler, ts_path: Path, source_root: Path
    ) -> None;

    def _copy_asset_file(
        self: JacClientCompiler, asset_path: Path, source_root: Path
    ) -> None;

    def copy_root_assets(self: JacClientCompiler) -> None;
    def _scan_and_compile_pages(
        self: JacClientCompiler,
        visited: (set[Path] | None) = None,
        collected_exports: (set[str] | None) = None,
        collected_globals: (dict[(str, Any)] | None) = None
    ) -> bool;

    def _generate_routes_manifest(self: JacClientCompiler) -> None;
    """Compile module + deps to ``.jac/client/compiled/`` (no entry file written)."""
    def compile(
        self: JacClientCompiler, module: ModuleType, module_path: Path
    ) -> tuple[list[str], list[str]];
}
