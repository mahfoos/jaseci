# React Native Basic

A minimal, cross-platform Jac client app for trying out the react-native target.

The same `main.jac` source compiles for both targets:

- `jac start main.jac --client web --dev`
- `jac start main.jac --client react-native --dev`

It uses only cross-platform primitives (inline style objects, no web-only CSS
imports) and stays auth-free so it runs cleanly on first launch. See the
`basic-auth` example for calling walkers behind authentication.

## Try the React Native flow

From this directory:

```bash
# 1. Scaffold the Expo / React Native project (creates ./mobile-rn)
jac setup react-native

# 2. Start the dev server and bundle the app for react-native
jac start main.jac --client react-native --dev
```

The web build still works the same way:

```bash
jac start main.jac --client web --dev
```

## Coverage surface

- Multi-screen navigation: `/` -> `/about`
- Component state via `has` (the counter)
- Event handlers (`onClick`) on a cross-platform `button`
