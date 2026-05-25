"""React Native Phase 3 multiscreen fixture (login -> home -> detail)."""

walker whoami {
    can execute with Root entry {
        report {"greeting": "Welcome back from walker"};
    }
}

cl {
    import from "@jac/runtime" {
        AuthGuard,
        JacForm,
        JacSchema,
        Link,
        Route,
        Router,
        Routes,
        jacLogin,
        jacLogout,
        useNavigate,
        useParams
    }

    def:pub app() -> JsxElement {
        return <Router>
            <div style={{padding: "1.5rem", fontFamily: "Arial, sans-serif"}}>
                <h1>RN Multiscreen Fixture</h1>
                <Routes>
                    <Route path="/" element={<LoginScreen />} />
                    <Route path="/login" element={<LoginScreen />} />
                    <Route path="/app" element={<AuthGuard redirect="/login" />}>
                        <Route path="home" element={<HomeScreen />} />
                        <Route path="detail/:id" element={<DetailScreen />} />
                    </Route>
                </Routes>
            </div>
        </Router>;
    }

    def LoginScreen() -> JsxElement {
        nav = useNavigate();
        loginSchema = JacSchema(
            {
                email: JacSchema.string().email("Invalid email"),
                password: JacSchema.string().min(
                    6, "Password must be at least 6 characters"
                )
            }
        );

        async def handleSubmit(data: dict) {
            await jacLogin(data.email, data.password);
            nav("/app/home");
        }

        return <div style={{maxWidth: "520px"}}>
            <h2>Login</h2>
            <p>Use any credentials for this fixture app.</p>
            <JacForm
                schema={loginSchema}
                onSubmit={handleSubmit}
                submitLabel="Sign in"
                field_config={{
                    "email": {
                        label: "Email",
                        type: "email",
                        placeholder: "you@example.com"
                    },
                    "password": {
                        label: "Password",
                        type: "password",
                        placeholder: "minimum 6 characters"
                    }
                }}
            />
        </div>;
    }

    def HomeScreen() -> JsxElement {
        nav = useNavigate();
        has greeting: str = "Loading greeting...";
        async can with entry {
            try {
                info = root spawn whoami();
                greeting = info.greeting if info and info.greeting else "Welcome";
            } except Exception {
                greeting = "Welcome";
            }
        }
        return <div>
            <h2>Home</h2>
            <p id="greeting">{greeting}</p>
            <div style={{display: "flex", gap: "12px"}}>
                <Link id="detail-link" to="/app/detail/42">Open detail #42</Link>
                <button
                    id="logout-btn"
                    onClick={lambda {
                        jacLogout();
                        nav("/login");
                    }}
                >
                    Log out
                </button>
            </div>
        </div>;
    }

    def DetailScreen() -> JsxElement {
        params = useParams();
        itemId = params.id if params and params.id else "unknown";
        return <div>
            <h2>Detail</h2>
            <p id="detail-id">Viewing item: {itemId}</p>
            <Link id="back-home-link" to="/app/home">Back to home</Link>
        </div>;
    }
}
