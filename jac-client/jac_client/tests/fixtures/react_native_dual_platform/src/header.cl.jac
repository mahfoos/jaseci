"""Web-specific Header component — renders with HTML semantics + CSS class."""

cl {
    # This is the WEB variant — uses className and HTML-native elements.
    # The CSS class "header-bar" comes from styles.css.
    def:pub PlatformHeader(props: dict) -> JsxElement {
        title = props.title if props and props.title else "App";
        return <header className="header-bar" style={{padding: "1rem", borderBottom: "1px solid #e5e7eb"}}>
            <h1 style={{margin: "0"}}>{title}</h1>
            <span className="header-badge">web</span>
        </header>;
    }
}
