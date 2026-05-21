"""Mobile-first Todo app with full CRUD backed by Jac server walkers."""

node Todo {
    has text: str,
        done: bool = False;
}

walker:pub read_todos {
    can read with Root entry {
        visit [-->[?:Todo]];
    }

    can report_todos with Todo entry {
        report here;
    }
}

walker:pub create_todo {
    has text: str;

    can create with Root entry {
        new_todo = here ++> Todo(text=self.text);
        report new_todo;
    }
}

walker:pub toggle_todo {
    can toggle with Todo entry {
        here.done = not here.done;
        report here;
    }
}

walker:pub delete_todo {
    can remove with Todo entry {
        del here;
        report {"deleted": True};
    }
}

cl {
    def:pub app -> JsxElement {
        has todos: list = [],
            inputText: str = "",
            loading: bool = True,
            adding: bool = False;

        async can with entry {
            try {
                result = root spawn read_todos();
                todos = result.reports;
            } except Exception as e {
                print(f"Failed to load todos: {e}");
            }
            loading = False;
        }

        async def addTodo {
            if not inputText.strip() {
                return;
            }
            adding = True;
            response = root spawn create_todo(text=inputText.strip());
            new_todo = response.reports[0][0];
            todos = todos.concat([new_todo]);
            inputText = "";
            adding = False;
        }

        async def toggleTodo(id: any) {
            result = id spawn toggle_todo();
            updated = result.reports[0];
            todos = [updated if t._jac_id == id else t for t in todos];
        }

        async def deleteTodo(id: any) {
            id spawn delete_todo();
            todos = [
                t
                for t in todos
                if t._jac_id != id
            ];
        }

        def handleKey(e: any) {
            if e.key == "Enter" {
                addTodo();
            }
        }

        done_count = len(
            [
                t
                for t in todos
                if t.done
            ]
        );
        remaining = len(todos) - done_count;
        total = len(todos);

        if loading {
            return
                <div
                    style={{
                        "minHeight": "100vh",
                        "display": "flex",
                        "alignItems": "center",
                        "justifyContent": "center",
                        "backgroundColor": "#f5f3ff",
                        "fontFamily": "system-ui, -apple-system, 'Apple Color Emoji', sans-serif"
                    }}
                >
                    <div style={{"textAlign": "center"}}>
                        <div style={{"fontSize": "2.5rem", "marginBottom": "0.75rem"}}>
                            ⏳
                        </div>
                        <p
                            style={{
                                "color": "#7c6fcd",
                                "fontSize": "0.95rem",
                                "margin": "0"
                            }}
                        >
                            Loading your tasks...
                        </p>
                    </div>
                </div>;
        }

        return
            <div
                style={{
                    "minHeight": "100vh",
                    "backgroundColor": "#f5f3ff",
                    "fontFamily": "system-ui, -apple-system, 'Apple Color Emoji', 'Noto Color Emoji', sans-serif"
                }}
            >
                <div
                    style={{
                        "background": "linear-gradient(135deg, #6366f1 0%, #4f46e5 60%, #4338ca 100%)",
                        "paddingTop": "calc(env(safe-area-inset-top, 0px) + 1.25rem)",
                        "paddingBottom": "1.75rem",
                        "paddingLeft": "1.5rem",
                        "paddingRight": "1.5rem",
                        "color": "#ffffff"
                    }}
                >
                    <div
                        style={{
                            "display": "flex",
                            "alignItems": "center",
                            "justifyContent": "space-between",
                            "marginBottom": "0.4rem"
                        }}
                    >
                        <h1
                            style={{
                                "margin": "0",
                                "fontSize": "1.8rem",
                                "fontWeight": "800",
                                "letterSpacing": "-0.02em"
                            }}
                        >
                            My Todos
                        </h1>
                        {(
                            <span
                                style={{
                                    "backgroundColor": "rgba(255,255,255,0.22)",
                                    "color": "#fff",
                                    "fontSize": "0.78rem",
                                    "fontWeight": "600",
                                    "padding": "0.25rem 0.8rem",
                                    "borderRadius": "999px"
                                }}
                            >
                                {done_count}/{total} done
                            </span>
                        )
                            if total > 0
                            else <span></span>}
                    </div>
                    <p
                        style={{
                            "margin": "0 0 1.1rem",
                            "fontSize": "0.88rem",
                            "opacity": "0.85"
                        }}
                    >
                        {remaining} task{"s" if remaining != 1 else ""} remaining
                    </p>
                    {(
                        <div
                            style={{
                                "backgroundColor": "rgba(255,255,255,0.2)",
                                "borderRadius": "999px",
                                "height": "5px",
                                "overflow": "hidden"
                            }}
                        >
                            <div
                                style={{
                                    "backgroundColor": "#ffffff",
                                    "height": "100%",
                                    "width": f"{done_count * 100 // total}%",
                                    "borderRadius": "999px"
                                }}
                            ></div>
                        </div>
                    )
                        if total > 0
                        else <span></span>}
                </div>
                <div style={{"padding": "1.25rem 1rem 6rem"}}>
                    <div
                        style={{
                            "display": "flex",
                            "gap": "0.5rem",
                            "marginBottom": "1.5rem",
                            "backgroundColor": "#ffffff",
                            "borderRadius": "16px",
                            "padding": "0.4rem 0.4rem 0.4rem 1rem",
                            "boxShadow": "0 4px 20px rgba(99,102,241,0.13)"
                        }}
                    >
                        <input
                            type="text"
                            value={inputText}
                            onChange={lambda e: any { inputText = e.target.value; }}
                            onKeyPress={handleKey}
                            placeholder="What needs to be done?"
                            style={{
                                "flex": "1",
                                "padding": "0.65rem 0",
                                "fontSize": "0.95rem",
                                "border": "none",
                                "outline": "none",
                                "backgroundColor": "transparent",
                                "color": "#1f2937"
                            }}
                        />
                        <button
                            onClick={addTodo}
                            disabled={adding}
                            style={{
                                "padding": "0.7rem 1.2rem",
                                "backgroundColor": ("#c7d2fe" if adding else "#6366f1"),
                                "color": "#ffffff",
                                "border": "none",
                                "borderRadius": "12px",
                                "fontSize": "1.4rem",
                                "fontWeight": "700",
                                "cursor": ("not-allowed" if adding else "pointer"),
                                "minWidth": "48px",
                                "lineHeight": "1"
                            }}
                        >
                            +
                        </button>
                    </div>
                    {(
                        <div style={{"textAlign": "center", "padding": "4rem 1rem"}}>
                            <div style={{"fontSize": "3.5rem", "marginBottom": "1rem"}}>
                                📝
                            </div>
                            <p
                                style={{
                                    "fontSize": "1rem",
                                    "fontWeight": "600",
                                    "color": "#6366f1",
                                    "margin": "0 0 0.25rem"
                                }}
                            >
                                No tasks yet
                            </p>
                            <p
                                style={{
                                    "fontSize": "0.85rem",
                                    "color": "#9ca3af",
                                    "margin": "0"
                                }}
                            >
                                Add your first task above
                            </p>
                        </div>
                    )
                        if total == 0
                        else (
                            <div
                                style={{
                                    "display": "flex",
                                    "flexDirection": "column",
                                    "gap": "0.5rem"
                                }}
                            >
                                {[
                                    <div
                                        key={t._jac_id}
                                        style={{
                                            "backgroundColor": "#ffffff",
                                            "borderRadius": "14px",
                                            "padding": "0.9rem 0.9rem 0.9rem 0",
                                            "display": "flex",
                                            "alignItems": "center",
                                            "gap": "0.75rem",
                                            "boxShadow": "0 2px 10px rgba(99,102,241,0.07)",
                                            "borderLeft": (
                                                "4px solid #6366f1"
                                                    if t.done
                                                    else "4px solid #e0e7ff"
                                            ),
                                            "opacity": ("0.7" if t.done else "1"),
                                            "overflow": "hidden"
                                        }}
                                    >
                                        <button
                                            onClick={lambda { toggleTodo(t._jac_id); }}
                                            style={{
                                                "width": "28px",
                                                "height": "28px",
                                                "minWidth": "28px",
                                                "borderRadius": "50%",
                                                "border": "2px solid #6366f1",
                                                "backgroundColor": (
                                                    "#6366f1"
                                                        if t.done
                                                        else "transparent"
                                                ),
                                                "cursor": "pointer",
                                                "display": "flex",
                                                "alignItems": "center",
                                                "justifyContent": "center",
                                                "color": "#ffffff",
                                                "fontSize": "0.9rem",
                                                "fontWeight": "700",
                                                "padding": "0",
                                                "flexShrink": "0",
                                                "marginLeft": "0.9rem"
                                            }}
                                        >
                                            {"✓" if t.done else ""}
                                        </button>
                                        <span
                                            style={{
                                                "flex": "1",
                                                "fontSize": "0.95rem",
                                                "color": (
                                                    "#a5b4fc" if t.done else "#1f2937"
                                                ),
                                                "textDecoration": (
                                                    "line-through" if t.done else "none"
                                                ),
                                                "fontWeight": "500",
                                                "wordBreak": "break-word"
                                            }}
                                        >
                                            {t.text}
                                        </span>
                                        <button
                                            onClick={lambda { deleteTodo(t._jac_id); }}
                                            style={{
                                                "width": "34px",
                                                "height": "34px",
                                                "minWidth": "34px",
                                                "backgroundColor": "#fef2f2",
                                                "color": "#ef4444",
                                                "border": "none",
                                                "borderRadius": "10px",
                                                "fontSize": "1.1rem",
                                                "cursor": "pointer",
                                                "display": "flex",
                                                "alignItems": "center",
                                                "justifyContent": "center",
                                                "padding": "0",
                                                "marginRight": "0.5rem",
                                                "flexShrink": "0"
                                            }}
                                        >
                                            ×
                                        </button>
                                    </div> for t in todos
                                ]}
                            </div>
                        )}
                </div>
            </div>;
    }
}
