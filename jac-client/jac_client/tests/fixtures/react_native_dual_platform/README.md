Dual-platform fixture. Tests that:

1. `.native.cl.jac` files are picked by the compiler when `target_name="react-native"`
2. `.cl.jac` files are used when `target_name="web"`
3. CSS imports are stripped from the native bundle

Structure:

- `main.jac` - entry point, imports `PlatformHeader` and a CSS file
- `src/header.cl.jac` - web variant (uses className, CSS)
- `src/header.native.cl.jac` - native variant (uses inline styles only)
- `src/styles.css` - web-only CSS, must be stripped from native build
