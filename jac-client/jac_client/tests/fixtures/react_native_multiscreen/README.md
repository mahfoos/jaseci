# React Native Multiscreen Fixture

Phase 3 fixture for `--client web` and `--client react-native` parity checks.

Coverage surface:

- Multi-screen navigation: `/login` -> `/app/home` -> `/app/detail/:id`
- Auth route wrapper: `AuthGuard redirect="/login"`
- Form parity: `JacForm` login screen (`email` + `password`)
- Walker call from client: `root spawn whoami()`
