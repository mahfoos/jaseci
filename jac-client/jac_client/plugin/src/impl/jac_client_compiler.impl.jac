import from jaclang.cli.console { console }

"""Get the client build directory from project config."""
impl JacClientCompiler._get_client_dir(self: JacClientCompiler) -> Path {
    try {
        import from jaclang.project.config { get_config }
        config = get_config();
        if config is not None {
            return config.get_client_dir();
        }
    } except ImportError { }
    return self.project_dir / '.jac' / 'client';
}

"""Convert a .jac relative path string to .js, handling compound extensions."""
impl JacClientCompiler._jac_path_to_js(self: JacClientCompiler, rel_str: str) -> str {
    rel_str = rel_str.replace('\\', '/');
    for compound_ext in self.COMPOUND_EXTENSIONS {
        if rel_str.endswith(compound_ext) {
            return rel_str[:-len(compound_ext)] + '.js';
        }
    }
    result = str(Path(rel_str).with_suffix('.js'));
    return result.replace('\\', '/');
}

"""Compile module and dependencies into the compiled/ directory.

This is the platform-neutral half of what ``ViteCompiler.compile`` used to do —
it does *not* write the web ``_entry.js``. Bundler-specific orchestrators
(``ViteCompiler`` for web, future ``MetroCompiler`` for native) layer their
entry generation on top of this output.
"""
impl JacClientCompiler.compile(
    self: JacClientCompiler, module: ModuleType, module_path: Path
) -> tuple[list[str], list[str]] {
    (module_js, mod, module_manifest) = self.jac_compiler.compile_module(module_path);
    collected_exports: set[str] = set(
        self.jac_compiler.extract_exports(module_manifest)
    );
    client_globals_map = self.jac_compiler.extract_globals(module_manifest, module);
    collected_globals: dict[(str, Any)] = dict(client_globals_map);
    visited: set[Path] = set();
    self.compile_dependencies_recursively(
        module_path,
        visited=visited,
        collected_exports=collected_exports,
        collected_globals=collected_globals
    );
    self._has_pages = self._scan_and_compile_pages(
        visited=visited,
        collected_exports=collected_exports,
        collected_globals=collected_globals
    );
    self.compile_runtime_utils();
    import from jac_client.plugin.src.config_loader { JacClientConfig as PwaConfig }
    pwa_config = PwaConfig(self.project_dir);
    if pwa_config.is_pwa_enabled() {
        self.compile_pwa_runtime();
    }
    self.copy_root_assets();
    client_exports = sorted(collected_exports);
    client_globals = list(collected_globals.keys());
    return (client_exports, client_globals);
}

"""Copy assets from root assets/ folder to compiled/assets/."""
impl JacClientCompiler.copy_root_assets(self: JacClientCompiler) -> None {
    root_assets_dir = self.project_dir / 'assets';
    compiled_assets_dir = self.compiled_dir / 'assets';
    if (root_assets_dir.exists() and root_assets_dir.is_dir()) {
        self.asset_processor.copy_assets(root_assets_dir, compiled_assets_dir);
        self.asset_processor.copy_custom_asset_types(
            root_assets_dir, compiled_assets_dir
        );
    }
}

"""Copy an asset file to the compiled directory."""
impl JacClientCompiler._copy_asset_file(
    self: JacClientCompiler, asset_path: Path, source_root: Path
) -> None {
    if not asset_path.exists() {
        return;
    }
    try {
        relative_path = asset_path.relative_to(source_root);
        output_path = self.compiled_dir / relative_path;
    } except ValueError {
        output_path = self.compiled_dir / asset_path.name;
    }
    output_path.parent.mkdir(parents=True, exist_ok=True);
    try {
        output_path.write_text(
            asset_path.read_text(encoding='utf-8'), encoding='utf-8'
        );
    } except (FileNotFoundError, OSError) as e {
        console.warning(f"Failed to copy asset '{asset_path}' to '{output_path}': {e}");
    }
}

"""Copy a TypeScript file to the compiled directory."""
impl JacClientCompiler._copy_ts_file(
    self: JacClientCompiler, ts_path: Path, source_root: Path
) -> None {
    if not ts_path.exists() {
        return;
    }
    try {
        ts_code = ts_path.read_text(encoding='utf-8');
        try {
            relative_path = ts_path.relative_to(source_root);
            output_path = self.compiled_dir / relative_path;
        } except ValueError {
            output_path = self.compiled_dir / ts_path.name;
        }
        output_path.parent.mkdir(parents=True, exist_ok=True);
        output_path.write_text(ts_code, encoding='utf-8');
    } except (FileNotFoundError, OSError) { }
}

"""Copy a JavaScript file to the compiled directory."""
impl JacClientCompiler._copy_js_file(
    self: JacClientCompiler, js_path: Path, source_root: Path
) -> None {
    try {
        js_code = js_path.read_text(encoding='utf-8');
        try {
            relative_path = js_path.relative_to(source_root);
            output_path = self.compiled_dir / relative_path;
        } except ValueError {
            output_path = self.compiled_dir / js_path.name;
        }
        output_path.parent.mkdir(parents=True, exist_ok=True);
        output_path.write_text(js_code, encoding='utf-8');
    } except FileNotFoundError { }
}

"""Recursively compile/copy .jac/.js imports into compiled/."""
impl JacClientCompiler.compile_dependencies_recursively(
    self: JacClientCompiler,
    module_path: Path,
    visited: (set[Path] | None) = None,
    collected_exports: (set[str] | None) = None,
    collected_globals: (dict[(str, Any)] | None) = None,
    source_root: (Path | None) = None
) -> None {
    if (visited is None) {
        visited = set();
    }
    if (collected_exports is None) {
        collected_exports = set();
    }
    if (collected_globals is None) {
        collected_globals = {};
    }
    module_path = module_path.resolve();
    if (module_path in visited) {
        return;
    }
    visited.add(module_path);
    if (source_root is None) {
        source_root = module_path.parent.resolve();
    }
    (module_js, mod, manifest) = self.jac_compiler.compile_module(module_path);
    exports_list = self.jac_compiler.extract_exports(manifest);
    collected_exports.update(exports_list);
    non_root_globals: dict[(str, Any)] = {};
    if manifest {
        for name in manifest.globals {
            non_root_globals[name] = manifest.globals_values.get(name);
        }
    }
    collected_globals.update(non_root_globals);
    combined_js = self.jac_compiler.add_runtime_imports(module_js);
    try {
        relative_path = module_path.relative_to(source_root);
        rel_str = self._jac_path_to_js(str(relative_path));
        output_path = self.compiled_dir / rel_str;
    } except ValueError {
        name = self._jac_path_to_js(module_path.name);
        output_path = self.compiled_dir / name;
    }
    output_path.parent.mkdir(parents=True, exist_ok=True);
    source_header = f"/* Source: {module_path} */\n";
    output_path.write_text(source_header + combined_js, encoding='utf-8');
    # Source map generation: matches the .jac → .js mapping the runtime expects.
    try {
        import from jaclang.runtimelib.source_mapping { generate_source_map_json }
        import from jaclang.jac0core.runtime { JacRuntime as Jac }
        hub_key = str(module_path);
        hub_mod = Jac.program.mod.hub.get(hub_key);
        if hub_mod and hub_mod.gen.es_ast {
            import from jaclang.compiler.passes.ecmascript.es_unparse {
                es_to_js_with_map
            }
            (_, line_map) = es_to_js_with_map(hub_mod.gen.es_ast);
            if line_map {
                raw_js = hub_mod.gen.js or '';
                full_output = source_header + combined_js;
                raw_start_idx = full_output.find(raw_js);
                if raw_start_idx > 0 {
                    prefix = full_output[:raw_start_idx];
                    header_lines = prefix.count('\n');
                } else {
                    header_lines = 0;
                }
                if header_lines > 0 {
                    line_map = [
                        (out + header_lines, src_l, src_c)
                        for (out, src_l, src_c) in line_map
                    ];
                }
                map_json = generate_source_map_json(
                    source_file=str(module_path),
                    output_file=output_path.name,
                    line_map=line_map
                );
                map_path = output_path.parent / f"{output_path.name}.map";
                map_path.write_text(map_json, encoding='utf-8');
                with open(output_path, 'a', encoding='utf-8') as f {
                    f.write(f"\n//# sourceMappingURL={output_path.name}.map\n");
                }
            }
        }
    } except Exception as e {
        console.warning(f"Failed to generate source map for '{module_path}': {e}");
    }
    if (not manifest or not manifest.imports) {
        return;
    }
    for (_name, import_path) in manifest.imports.items() {
        path_obj = Path(import_path).resolve();
        if (path_obj in visited) {
            continue;
        }
        if (path_obj.suffix == '.jac') {
            self.compile_dependencies_recursively(
                path_obj,
                visited,
                collected_exports=collected_exports,
                collected_globals=collected_globals,
                source_root=source_root
            );
        } elif (path_obj.suffix == '.js') {
            self._copy_js_file(path_obj, source_root);
        } elif (path_obj.suffix in {'.ts', '.tsx'}) {
            self._copy_ts_file(path_obj, source_root);
        } elif path_obj.is_file() {
            self._copy_asset_file(path_obj, source_root);
        }
    }
}

"""Compile client runtime utilities."""
impl JacClientCompiler.compile_runtime_utils(
    self: JacClientCompiler
) -> tuple[str, list[str]] {
    if not self.runtime_path {
        raise ClientBundleError('Runtime path not set');
    }
    runtime_utils_path = self.runtime_path.parent / 'client_runtime.cl.jac';
    (runtimeutils_js, mod, runtimeutils_manifest) = self.jac_compiler.compile_module(
        runtime_utils_path
    );
    runtimeutils_exports_list = self.jac_compiler.extract_exports(
        runtimeutils_manifest
    );
    glob_names = list(runtimeutils_manifest.globals) if runtimeutils_manifest else [];
    all_exports = sorted(
        set(runtimeutils_exports_list + self.ROUTER_EXPORTS + glob_names)
    );
    self.compiled_dir.mkdir(parents=True, exist_ok=True);
    (self.compiled_dir / 'client_runtime.js').write_text(
        runtimeutils_js, encoding='utf-8'
    );
    return (runtimeutils_js, all_exports);
}

"""Compile PWA runtime utilities (only when PWA is enabled)."""
impl JacClientCompiler.compile_pwa_runtime(
    self: JacClientCompiler
) -> tuple[str, list[str]] {
    runtime_path = self.runtime_path;
    if runtime_path is None {
        return ('', []);
    }
    pwa_runtime_path: Path = runtime_path.parent / 'pwa_runtime.cl.jac';
    if not pwa_runtime_path.exists() {
        return ('', []);
    }
    (pwa_js, mod, pwa_manifest) = self.jac_compiler.compile_module(pwa_runtime_path);
    pwa_exports_list = self.jac_compiler.extract_exports(pwa_manifest);
    glob_names = list(pwa_manifest.globals) if pwa_manifest else [];
    all_exports = sorted(set(pwa_exports_list + glob_names));
    self.compiled_dir.mkdir(parents=True, exist_ok=True);
    (self.compiled_dir / 'pwa_runtime.js').write_text(pwa_js, encoding='utf-8');
    return (pwa_js, all_exports);
}

"""Scan pages/ directory, compile page files, generate _routes.js manifest."""
impl JacClientCompiler._scan_and_compile_pages(
    self: JacClientCompiler,
    visited: (set[Path] | None) = None,
    collected_exports: (set[str] | None) = None,
    collected_globals: (dict[(str, Any)] | None) = None
) -> bool {
    scanner = RouteScanner(self.project_dir);
    if not scanner.has_pages_dir() {
        return False;
    }
    routes = scanner.scan();
    if not routes and not scanner.get_layouts() {
        return False;
    }
    self._route_scanner = scanner;
    source_root = self.project_dir;
    for page_file in scanner.get_page_files() {
        self.compile_dependencies_recursively(
            page_file,
            visited=visited,
            collected_exports=collected_exports,
            collected_globals=collected_globals,
            source_root=source_root
        );
    }
    self._generate_routes_manifest();
    return True;
}

"""Generate _routes.js manifest from previously scanned route entries."""
impl JacClientCompiler._generate_routes_manifest(self: JacClientCompiler) -> None {
    scanner = self._route_scanner;
    routes = scanner._routes;
    layouts = scanner.get_layouts();
    lines: list[str] = [];
    for route in routes {
        if route.is_layout {
            continue;
        }
        try {
            rel_path = route.file_path.relative_to(self.project_dir);
        } except ValueError {
            rel_path = route.file_path.relative_to(scanner.pages_dir.parent);
        }
        rel_str = self._jac_path_to_js(str(rel_path));
        lines.append(
            f'import {{ page as {route.component_import} }} from "./{rel_str}";'
        );
    }
    for (prefix, layout) in layouts.items() {
        try {
            rel_path = layout.file_path.relative_to(self.project_dir);
        } except ValueError {
            rel_path = layout.file_path.relative_to(scanner.pages_dir.parent);
        }
        rel_str = self._jac_path_to_js(str(rel_path));
        lines.append(
            f'import {{ layout as {layout.component_import} }} from "./{rel_str}";'
        );
    }
    lines.append('');
    lines.append('export const routes = [');
    for route in routes {
        if route.is_layout {
            continue;
        }
        auth_str = "true" if route.auth_required else "false";
        lines.append(
            f'\t{{ path: "{route.path}", element: {route.component_import}, auth: {auth_str} }},'
        );
    }
    lines.append('];');
    lines.append('');
    lines.append('export const layouts = {');
    for (prefix, layout) in layouts.items() {
        lines.append(f'\t"{prefix}": {layout.component_import},');
    }
    lines.append('};');
    lines.append('');
    manifest_path = self.compiled_dir / '_routes.js';
    manifest_path.parent.mkdir(parents=True, exist_ok=True);
    manifest_path.write_text("\n".join(lines), encoding='utf-8');
}

"""Initialize the platform-neutral Jac client compiler."""
impl JacClientCompiler.init(
    self: JacClientCompiler,
    project_dir: Path,
    runtime_path: (Path | None),
    compile_to_js_func: Callable[([Path], tuple[(str, (ModuleType | None))])],
    extract_exports_func: Callable[([any], list[str])],
    extract_globals_func: Callable[([any, ModuleType], dict[(str, Any)])],
    compiled_dir: (Path | None) = None
) {
    self.project_dir = project_dir;
    self.runtime_path = runtime_path;
    self.compiled_dir = compiled_dir
        if compiled_dir is not None
        else (self._get_client_dir() / 'compiled');
    self.jac_compiler = JacToJSCompiler(
        compile_to_js_func, extract_exports_func, extract_globals_func
    );
    self.import_processor = ImportProcessor();
    self.asset_processor = AssetProcessor();
    self._has_pages = False;
    self._route_scanner = None;
}
