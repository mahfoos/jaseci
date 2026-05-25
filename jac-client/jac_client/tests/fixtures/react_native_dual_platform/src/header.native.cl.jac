"""React Native-specific Header component — renders with View/Text primitives.

This file (header.native.cl.jac) is picked by the compiler when
target_name="react-native" instead of header.cl.jac. It uses RN-compatible
primitives only (no className, no CSS classes, no HTML-specific tags).
"""

cl {
    def:pub PlatformHeader(props: dict) -> JsxElement {
        title = props.title if props and props.title else "App";
        return <header style={{padding: "1rem", borderBottom: "1px solid #e5e7eb"}}>
            <h1 style={{margin: "0"}}>{title}</h1>
            <span style={{fontSize: "12px", color: "#6b7280"}}>native</span>
        </header>;
    }
}
