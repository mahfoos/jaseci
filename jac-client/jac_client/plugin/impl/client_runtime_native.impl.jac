# React Native runtime (D9). Shared logic lives in client_runtime_core.
impl __jacWirePlatformAdapters -> None {
    globalThis.__jacGetRenderer__ = __jacGetRenderer;
    globalThis.__jacGetApiBaseUrl__ = __jacGetApiBaseUrl;
    globalThis.__jacGetLocalStorage__ = __getLocalStorage;
    globalThis.__jacSetLocalStorage__ = __setLocalStorage;
    globalThis.__jacRemoveLocalStorage__ = __removeLocalStorage;
    globalThis.__jacSeedEndpointEffects__ = lambda -> dict {
        seed = globalThis.__JAC_INIT__;
        if seed and seed.endpointEffects {
            return seed.endpointEffects;
        }
        return {};
    };
    globalThis.__jacHandleWalkerUnauthorized__ = lambda { console.warn(
        "[jac-native-runtime] Walker returned 401; cleared token. "
        "App should redirect to login."
    ); };
    globalThis.__jacDefaultErrorReportUrl__ = lambda -> str { return ""; };
}

impl __jacGetRenderer -> any {
    if not globalThis.__jacRenderer__ {
        globalThis.__jacRenderer__ = {"create": __jacNativeCreate};
    }
    return globalThis.__jacRenderer__;
}

glob _VIEW_TAGS = [
         "div",
         "section",
         "main",
         "article",
         "header",
         "footer",
         "nav",
         "aside",
         "ul",
         "ol",
         "li",
         "form"
     ],
     _TEXT_TAGS = [
         "span",
         "p",
         "h1",
         "h2",
         "h3",
         "h4",
         "h5",
         "h6",
         "label",
         "strong",
         "em",
         "small"
     ],
     _UNMAPPED_WARNED = {};

impl __jacNativeCreate(tag: any, props: dict = {}, children: any = []) -> JsxElement {
    if tag == None {
        tag = React.Fragment;
    }
    childrenArray = [];
    if children != None {
        if Array.isArray(children) {
            childrenArray = children;
        } else {
            childrenArray = [children];
        }
    }
    flat = [];
    for child in childrenArray {
        if child == None or child == undefined {
            continue;
        }
        flat.append(child);
    }
    if typeof(tag) != "string" {
        args = [tag, props];
        for child in flat {
            args.append(child);
        }
        return React.createElement.apply(React, args);
    }
    adapted = _adaptProps(tag, props);
    if _VIEW_TAGS.includes(tag) {
        args = [RNView, adapted];
        for child in flat {
            args.append(child);
        }
        return React.createElement.apply(React, args);
    }
    if _TEXT_TAGS.includes(tag) {
        args = [RNText, adapted];
        for child in flat {
            args.append(child);
        }
        return React.createElement.apply(React, args);
    }
    if tag == "button" {
        textChild = React.createElement.apply(React, _prepend_args(RNText, None, flat));
        return React.createElement(RNPressable, adapted, textChild);
    }
    if tag == "input" or tag == "textarea" {
        if tag == "textarea" {
            adapted["multiline"] = True;
        }
        return React.createElement(RNTextInput, adapted);
    }
    if tag == "img" {
        return React.createElement(RNImage, adapted);
    }
    if tag == "a" {
        return _makeNativeLink(adapted, flat);
    }
    if not _UNMAPPED_WARNED[tag] {
        _UNMAPPED_WARNED[tag] = True;
        console.warn(
            f"[jac-native-runtime] Unmapped HTML tag <{tag}>. Rendering as "
            "<View> with a debug border."
        );
    }
    debug_adapted = adapted;
    if globalThis.__DEV__ {
        existing_style = adapted["style"] if adapted["style"] else None;
        unmapped_style = {
            "borderWidth": 1,
            "borderColor": "red",
            "borderStyle": "dashed"
        };
        debug_adapted = Object.assign({}, adapted);
        debug_adapted["style"] = [unmapped_style, existing_style]
            if existing_style
            else unmapped_style;
    }
    args = [RNView, debug_adapted];
    for child in flat {
        args.append(child);
    }
    return React.createElement.apply(React, args);
}

def _adaptProps(tag: str, props: dict) -> dict {
    if not props {
        return {};
    }
    out = {};
    keys = Object.keys(props);
    for key in keys {
        value = props[key];
        if value == None or value == undefined {
            continue;
        }
        if key == "class" or key == "className" {
            out["accessibilityLabel"] = str(value);
        } elif key == "style" {
            out["style"] = value;
        } elif key == "onClick" {
            out["onPress"] = value;
        } elif key == "onChange" {
            out["onChangeText"] = value;
        } elif key == "value"
        or key == "placeholder"
        or key == "editable"
        or key == "multiline"
        or key == "secureTextEntry"
        or key == "key"
        or key == "ref" {
            out[key] = value;
        } elif key.startsWith("data-") or key.startsWith("aria-") {
            continue;
        } else {
            out[key] = value;
        }
    }
    return out;
}

def _prepend_args(comp: any, props: any, children: list) -> list {
    args = [comp, props];
    for child in children {
        args.append(child);
    }
    return args;
}

def _makeNativeLink(props: dict, children: list) -> JsxElement {
    href = props["href"] if props["href"] else None;
    rest = Object.assign({}, props);
    if rest["href"] {
        Reflect.deleteProperty(rest, "href");
    }
    if href {
        rest["onPress"] = lambda { RNLinking.openURL(href).catch(
            lambda e: any { console.warn("RNLinking.openURL failed", e); }
        ); };
    }
    args = [RNText, rest];
    for child in children {
        args.append(child);
    }
    return React.createElement.apply(React, args);
}

impl __nativeRouterStub(props: dict = {}) -> JsxElement {
    raise Exception(
        "Router/Routes/Route/Link/Navigate/Outlet are Phase 3 features for "
        "the react-native target. See REACT_NATIVE_ARCHITECTURE.md (Phase 3)."
    );
}

impl useRouter -> dict {
    raise Exception(
        "useRouter is a Phase 3 feature for react-native — see "
        "REACT_NATIVE_ARCHITECTURE.md (Phase 3)."
    );
}

impl useNavigate -> any {
    raise Exception(
        "useNavigate is Phase 3 for react-native — see REACT_NATIVE_ARCHITECTURE.md."
    );
}

impl useLocation -> dict {
    return {"pathname": "/", "search": "", "hash": "", "state": None};
}

impl useParams -> dict {
    return {};
}

impl navigate(path: str) -> None {
    console.warn(
        f"[jac-native-runtime] navigate({path!r}) is a no-op until React "
        "Navigation lands in Phase 3."
    );
}

impl __getApiBaseUrl -> str {
    build_time = globalThis.__JAC_API_BASE_URL__;
    if build_time {
        return build_time;
    }
    try {
        cfg = ExpoConstants.expoConfig;
        if cfg and cfg.extra and cfg.extra.apiBaseUrl {
            return cfg.extra.apiBaseUrl;
        }
    } except Exception { }
    return "http://10.0.2.2:8000";
}

impl __getLocalStorage(key: str) -> str {
    if not globalThis.__jacNativeStorageCache__ {
        globalThis.__jacNativeStorageCache__ = {};
    }
    cache = globalThis.__jacNativeStorageCache__;
    if key in cache {
        return cache[key];
    }
    SecureStore.getItemAsync(key).then(
        lambda val: any { cache[key] = val or ""; }
    ).catch(
        lambda e: any { console.warn("SecureStore.getItemAsync failed", e); }
    );
    return "";
}

impl __setLocalStorage(key: str, value: str) -> None {
    if not globalThis.__jacNativeStorageCache__ {
        globalThis.__jacNativeStorageCache__ = {};
    }
    globalThis.__jacNativeStorageCache__[key] = value;
    SecureStore.setItemAsync(key, value).catch(
        lambda e: any { console.warn("SecureStore.setItemAsync failed", e); }
    );
}

impl __removeLocalStorage(key: str) -> None {
    if not globalThis.__jacNativeStorageCache__ {
        globalThis.__jacNativeStorageCache__ = {};
    }
    Reflect.deleteProperty(globalThis.__jacNativeStorageCache__, key);
    SecureStore.deleteItemAsync(key).catch(
        lambda e: any { console.warn("SecureStore.deleteItemAsync failed", e); }
    );
}

impl __getLocalStorageAsync(key: str) -> str {
    val = await SecureStore.getItemAsync(key);
    if not globalThis.__jacNativeStorageCache__ {
        globalThis.__jacNativeStorageCache__ = {};
    }
    globalThis.__jacNativeStorageCache__[key] = val or "";
    return val or "";
}

impl __setLocalStorageAsync(key: str, value: str) -> None {
    if not globalThis.__jacNativeStorageCache__ {
        globalThis.__jacNativeStorageCache__ = {};
    }
    globalThis.__jacNativeStorageCache__[key] = value;
    await SecureStore.setItemAsync(key, value);
}

impl __removeLocalStorageAsync(key: str) -> None {
    if not globalThis.__jacNativeStorageCache__ {
        globalThis.__jacNativeStorageCache__ = {};
    }
    Reflect.deleteProperty(globalThis.__jacNativeStorageCache__, key);
    await SecureStore.deleteItemAsync(key);
}

impl __primeNativeTokenCache -> None {
    try {
        token = await SecureStore.getItemAsync("jac_token");
        if not globalThis.__jacNativeStorageCache__ {
            globalThis.__jacNativeStorageCache__ = {};
        }
        globalThis.__jacNativeStorageCache__["jac_token"] = token or "";
    } except Exception as e {
        console.warn("[jac-native-runtime] __primeNativeTokenCache failed", e);
    }
}

impl AuthGuard(redirect: str = "/login") -> JsxElement {
    if jacIsLoggedIn() {
        return None;
    }
    return React.createElement(RNText, None, "Please log in (AuthGuard placeholder)");
}

impl ErrorFallback(error: str, resetErrorBoundary: any) -> JsxElement {
    err_obj = error.error if error and error.error else error;
    msg = err_obj.message if err_obj and err_obj.message else str(err_obj);
    reset_fn = error.resetErrorBoundary
        if error and error.resetErrorBoundary
        else resetErrorBoundary;
    return React.createElement(
        RNView,
        {"style": {"padding": 24, "flex": 1, "justifyContent": "center"}},
        React.createElement(
            RNText,
            {
                "style": {
                    "fontWeight": "bold",
                    "color": "#dc2626",
                    "fontSize": 18,
                    "marginBottom": 12
                }
            },
            "Something went wrong"
        ),
        React.createElement(
            RNText, {"style": {"color": "#374151", "marginBottom": 16}}, msg
        ),
        React.createElement(
            RNPressable,
            {
                "onPress": reset_fn,
                "style": {
                    "backgroundColor": "#2563eb",
                    "padding": 12,
                    "borderRadius": 8,
                    "alignSelf": "flex-start"
                }
            },
            React.createElement(
                RNText, {"style": {"color": "white", "fontWeight": "600"}}, "Try again"
            )
        )
    );
}

impl JacAwaiting(props: dict) -> JsxElement {
    return React.createElement(
        React.Suspense, {"fallback": props.fallback}, props.children
    );
}

impl errorOverlay(filePath: str, errors: str) -> JsxElement {
    return React.createElement(
        RNView,
        {"style": {"padding": 24, "flex": 1, "backgroundColor": "#1e1e1e"}},
        React.createElement(
            RNText,
            {
                "style": {
                    "color": "#ff6b6b",
                    "fontWeight": "bold",
                    "fontSize": 16,
                    "marginBottom": 12
                }
            },
            "Compilation Error"
        ),
        React.createElement(
            RNText, {"style": {"color": "#64b5f6", "marginBottom": 8}}, filePath
        ),
        React.createElement(
            RNText, {"style": {"color": "#ff6b6b", "fontFamily": "monospace"}}, errors
        )
    );
}

impl JacForm(props: dict) -> JsxElement {
    schema = props.schema;
    onSubmit = props.onSubmit;
    submitLabel = props.submitLabel || "Submit";
    field_config = props.field_config || {};
    actualSchema = schema;
    try {
        if schema._def and schema._def.schema {
            actualSchema = schema._def.schema;
        }
    } except Exception { }
    schemaShape = actualSchema.shape || {};
    fieldNames = Object.keys(schemaShape);
    form = useJacForm("onTouched", schema);
    isSubmitting = form.formState.isSubmitting;
    isDirty = form.formState.isDirty;
    fields = [];
    for fieldName in fieldNames {
        config = field_config[fieldName] if field_config[fieldName] else {};
        label = config.label or fieldName;
        placeholder = config.placeholder or "";
        field = form.register(fieldName, {});
        fields.append(
            React.createElement(
                RNView,
                {"key": fieldName, "style": {"marginBottom": 12}},
                React.createElement(
                    RNText, {"style": {"marginBottom": 4, "color": "#374151"}}, label
                ),
                React.createElement(
                    RNTextInput,
                    {
                        "placeholder": placeholder,
                        "onChangeText": field.onChange,
                        "onBlur": field.onBlur,
                        "style": {
                            "borderWidth": 1,
                            "borderColor": "#e5e7eb",
                            "padding": 8,
                            "borderRadius": 4
                        }
                    }
                )
            )
        );
    }
    submit_handler = lambda { form.handleSubmit(onSubmit)(); };
    args = [RNView, {"style": {"padding": 12}}];
    for f in fields {
        args.append(f);
    }
    args.append(
        React.createElement(
            RNPressable,
            {
                "onPress": submit_handler,
                "disabled": isSubmitting or not isDirty,
                "style": {
                    "backgroundColor": "#2563eb"
                        if (isDirty and not isSubmitting)
                        else "#9ca3af",
                    "padding": 12,
                    "borderRadius": 6,
                    "marginTop": 12
                }
            },
            React.createElement(
                RNText,
                {
                    "style": {
                        "color": "white",
                        "textAlign": "center",
                        "fontWeight": "600"
                    }
                },
                "Submitting..." if isSubmitting else submitLabel
            )
        )
    );
    return React.createElement.apply(React, args);
}

impl __jacInstallErrorHandlers -> None {
    __jacWirePlatformAdapters();
    if globalThis.__jacErrorHandlersInstalled {
        return;
    }
    globalThis.__jacErrorHandlersInstalled = True;
    try {
        __primeNativeTokenCache();
    } except Exception { }
    try {
        prev = globalThis.ErrorUtils.getGlobalHandler();
        globalThis.ErrorUtils.setGlobalHandler(
            lambda error: any , isFatal: any {
                message = error.message if error else "Unknown error";
                stack = error.stack if error else "";
                __jacReportError(message, stack, "", "ErrorUtils");
                if prev {
                    prev(error, isFatal);
                }
            }
        );
    } except Exception as e {
        console.warn("[jac-native-runtime] Failed to install ErrorUtils handler", e);
    }
}
