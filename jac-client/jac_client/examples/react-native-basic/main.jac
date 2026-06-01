"""Basic React Native sample app.

A minimal, cross-platform Jac client app meant for exercising the
react-native target:

    jac setup react-native
    jac start main.jac --client react-native --dev

It uses only cross-platform primitives (inline style objects, no web-only
CSS imports) so the same source compiles for both ``--client web`` and
``--client react-native``. It stays auth-free on purpose — it exercises
component state (``has``), navigation, and event handlers without a login
flow, so it runs cleanly on first launch. See the ``basic-auth`` example
for calling walkers behind authentication.

Layout note: ``<Routes>`` is the *direct* child of ``<Router>``. On the
react-native target ``<Routes>`` compiles to a navigation stack that must be
the layout root — wrapping it in another element (e.g. a padded ``<div>``
with a sibling heading) collapses the navigator to zero height and renders a
blank screen. Per-screen chrome lives inside each screen component instead.
"""

cl {
    import from "@jac/runtime" {
        Link,
        Route,
        Router,
        Routes
    }

    def:pub app() -> JsxElement {
        return <Router>
            <Routes>
                <Route path="/" element={<HomeScreen />} />
                <Route path="/about" element={<AboutScreen />} />
            </Routes>
        </Router>;
    }

    def HomeScreen() -> JsxElement {
        has count: int = 0;

        return <div style={{padding: 24}}>
            <h1 style={{fontSize: 26, fontWeight: "bold", marginBottom: 4}}>
                React Native Basic
            </h1>
            <h2 style={{fontSize: 18, fontWeight: "600", marginBottom: 12}}>
                Home
            </h2>
            <p id="count" style={{fontSize: 16, marginBottom: 16}}>
                Count: {count}
            </p>
            <button
                id="increment-btn"
                style={{
                    backgroundColor: "#2563eb",
                    color: "white",
                    fontSize: 16,
                    fontWeight: "600",
                    textAlign: "center",
                    paddingTop: 12,
                    paddingBottom: 12,
                    borderRadius: 8,
                    marginBottom: 12
                }}
                onClick={lambda e: any { count = count + 1; }}
            >
                Increment
            </button>
            <Link
                id="about-link"
                to="/about"
                style={{
                    color: "#2563eb",
                    fontSize: 16,
                    fontWeight: "600",
                    textAlign: "center",
                    paddingTop: 12,
                    paddingBottom: 12,
                    borderRadius: 8,
                    borderWidth: 1,
                    borderColor: "#2563eb"
                }}
            >
                Go to About
            </Link>
        </div>;
    }

    def AboutScreen() -> JsxElement {
        return <div style={{padding: 24}}>
            <h1 style={{fontSize: 22, fontWeight: "bold", marginBottom: 12}}>
                About
            </h1>
            <p style={{fontSize: 16, marginBottom: 16}}>
                The same Jac source compiles for both web and react-native.
            </p>
            <Link
                id="home-link"
                to="/"
                style={{color: "#2563eb", fontSize: 16, fontWeight: "600"}}
            >
                Back to home
            </Link>
        </div>;
    }
}
