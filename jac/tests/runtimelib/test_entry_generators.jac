"""Tests for the entry-generator registry.

The registry is the seam between core machinery (HMR, eject, the shared
client compiler step) and the active jac-client plugin. These tests
exercise it in isolation — they do not need a built bundle or a running
plugin, only the contract surface in `jaclang.runtimelib.entry_generators`.
"""

import from jaclang.runtimelib.entry_generators {
    register_entry_generator,
    get_entry_generator,
    has_entry_generator,
    clear_entry_generators
}

test "registered generator is returned by get_entry_generator" {
    clear_entry_generators();
    def stub(entry_module: str, install_global_handlers: bool = True) -> str {
        return f"stub({entry_module},{install_global_handlers})";
    }
    register_entry_generator("test", stub);
    fn = get_entry_generator("test");
    result = fn("main", install_global_handlers=False);
    assert result == "stub(main,False)";
    clear_entry_generators();
}

test "get_entry_generator raises LookupError when target is missing" {
    clear_entry_generators();
    raised = False;
    msg = "";
    try {
        get_entry_generator("never_registered");
    } except LookupError as e {
        raised = True;
        msg = str(e);
    }
    assert raised;
    assert "never_registered" in msg;
    assert "jac-client" in msg;
}

test "has_entry_generator reflects registration state" {
    clear_entry_generators();
    assert not has_entry_generator("web");
    def stub2(entry_module: str, install_global_handlers: bool = True) -> str {
        return "x";
    }
    register_entry_generator("web", stub2);
    assert has_entry_generator("web");
    clear_entry_generators();
    assert not has_entry_generator("web");
}

test "re-registering the same target overrides the previous generator" {
    clear_entry_generators();
    def first(entry_module: str, install_global_handlers: bool = True) -> str {
        return "first";
    }
    def second(entry_module: str, install_global_handlers: bool = True) -> str {
        return "second";
    }
    register_entry_generator("web", first);
    register_entry_generator("web", second);
    assert get_entry_generator("web")("main") == "second";
    clear_entry_generators();
}

test "jac-client web generator is wired through the registry" {
    # The `with entry { ... }` block in web_entry.jac runs once per process
    # at first import; Python caches the module so we can't observe the
    # side effect repeatedly across tests that clear the registry. Instead
    # we use importlib.reload to force a fresh execution of the registration.
    import importlib;
    clear_entry_generators();
    assert not has_entry_generator("web");
    import jac_client.plugin.src.entry_generators.web_entry as web_entry_mod;
    importlib.reload(web_entry_mod);
    assert has_entry_generator("web");
    assert has_entry_generator("web:error_overlay");
    # Sanity-check: the registered web generator IS the function exported
    # by web_entry.jac, not some other shim.
    fn = get_entry_generator("web");
    direct = web_entry_mod.build_simple_react_entry_script(
        "main", install_global_handlers=True
    );
    via_registry = fn("main", install_global_handlers=True);
    assert direct == via_registry;
}
