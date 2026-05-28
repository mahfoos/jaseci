"""Fixture: dual-platform component resolution.

Demonstrates that a Jac app can provide .cl.jac (web) and .native.cl.jac
(react-native) variants of the same component. The compiler picks the
native variant when target_name="react-native" and the web variant
otherwise.

This fixture also exercises:
  - CSS import (web-only; must be stripped from the native bundle)
  - Inline style objects (cross-platform)
  - Walker call (shared logic)
"""

walker get_greeting {
    can execute with Root entry {
        report {"greeting": "Hello from dual-platform fixture!"};
    }
}

cl {
    import from "@jac/runtime" {
        JacSchema,
        Link,
        Route,
        Router,
        Routes,
        useNavigate
    }
    # Platform-specific Header component
    import from "./src/header.cl.jac" { PlatformHeader }

    # CSS import — web-only. The RN build must strip this.
    cl import "./src/styles.css";

    def:pub app() -> JsxElement {
        return <Router>
            <div style={{fontFamily: "Arial, sans-serif"}}>
                <PlatformHeader title="Dual Platform Demo" />
                <Routes>
                    <Route path="/" element={<HomeScreen />} />
                    <Route path="/about" element={<AboutScreen />} />
                </Routes>
            </div>
        </Router>;
    }

    def HomeScreen() -> JsxElement {
        nav = useNavigate();
        has message: str = "Loading...";
        async can with entry {
            try {
                result = root spawn get_greeting();
                message = result.greeting if result and result.greeting else "Hi";
            } except Exception {
                message = "Hello (offline)";
            }
        }
        return <div style={{padding: "1rem"}}>
            <h2>Home</h2>
            <p id="greeting">{message}</p>
            <Link to="/about">About</Link>
        </div>;
    }

    def AboutScreen() -> JsxElement {
        return <div style={{padding: "1rem"}}>
            <h2>About</h2>
            <p>This fixture tests .native.cl.jac platform resolution.</p>
        </div>;
    }
}
