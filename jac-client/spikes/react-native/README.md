# React Native - Phase 0 Spike

**Status:** complete on 2026-05-23. **Recommendation: GO** for refactors R1+R2+R3.

This directory implements Phase 0 of the React Native plan in
[`REACT_NATIVE_ARCHITECTURE.md`](../../../REACT_NATIVE_ARCHITECTURE.md). It is a
hand-wired Expo app that consumes a pre-compiled Jac bundle through Metro and
renders Jac JSX via a tag-mapping renderer (`native_runtime.ts`), then proves
a `jacSpawn` call against a running `jac start` backend.

**No plugin changes.** Nothing under `jac-client/jac_client/plugin/**` or
`jac/jaclang/**` was touched.

---

## Layout

```
spikes/react-native/
  README.md              -- you are here
  package.json           -- Expo SDK 52, Hermes + New Architecture
  app.json               -- expo config, apiBaseUrl in `extra`
  metro.config.js        -- watchFolders + @jac/runtime resolver (Q5)
  tsconfig.json
  babel.config.js
  index.ts               -- AppRegistry entry (mirrors R2's future generator)
  App.tsx                -- screen mounting the compiled Jac `app` + ping panel
  native_runtime.ts      -- the spike's renderer + walker fetch + storage
  jac-compiled/          -- output of compiling basic-app/app.jac
    main.js              -- imports `@jac/runtime`, uses __jacJsx("div", ...)
    main.js.map
  backend/
    main.jac             -- `ping` walker for the round-trip
```

## How `jac-compiled/main.js` was produced

```bash
cd /tmp
jac create jac-spike-build --use client
cd jac-spike-build
cp <repo>/jac-client/jac_client/tests/fixtures/basic-app/app.jac main.jac
jac build main.jac          # web build fails late at Vite step, that is fine
cp .jac/client/compiled/main.js     <repo>/jac-client/spikes/react-native/jac-compiled/
cp .jac/client/compiled/main.js.map <repo>/jac-client/spikes/react-native/jac-compiled/
```

We only need the `compiled/main.js` artifact - not the `_entry.js` (web-DOM
specific) and not `client_runtime.js` (web-bound runtime). Our
`native_runtime.ts` *is* the runtime for this spike, supplied to the bundle
via Metro resolver.

---

## Running

### 1. Install

```bash
cd jac-client/spikes/react-native
npm install
```

### 2. Start the backend (on the host machine)

```bash
cd backend
jac start main.jac --no-client --host 0.0.0.0 -a 8000
```

The default `apiBaseUrl` in `app.json` is `http://10.0.2.2:8000`, the Android
emulator's loopback to the host. If you're on a physical device, edit
`app.json` -> `expo.extra.apiBaseUrl` to your host's LAN IP.

### 3. Build and launch the app

```bash
npx expo run:android
```

This runs `expo prebuild` to generate the native `android/` project, then
`gradlew assembleDebug` and `adb install`. First build is slow (5-10 minutes);
incremental rebuilds are seconds.

### 4. Verify

- The top half of the screen shows "Runtime Test" and a "Tap Me" button -
  these come from `jac-compiled/main.js` rendered through `__jacJsx` ->
  `<View>` / `<Text>` / `<Pressable>`.
- Tap **Call ping** in the bottom panel. The result area should show JSON
  with `"ok": true`, a timestamp, and `"message": "pong from jac"`.

---

## Findings (Phase 0 deliverable)

### What worked

1. **Metro resolver for `@jac/runtime`.** Both `extraNodeModules` and a
   `resolveRequest` hook successfully redirect the bare import in compiled Jac
   JS to our local `native_runtime.ts`. Verified by:

   ```
   $ npx expo export --platform android --output-dir /tmp/t --no-bytecode
   Android Bundled 11209ms index.ts (552 modules)
   $ grep -c "jac-native-runtime\|VIEW_TAGS\|doWalkerFetch\|API_LABEL\|Runtime Test\|__jacJsx" /tmp/t/_expo/static/js/android/*.js
   21
   ```

   Both the compiled Jac bundle (`API_LABEL`, `"Runtime Test"`, `__jacJsx`
   calls) and our native runtime (`VIEW_TAGS`, `doWalkerFetch`,
   `[jac-native-runtime]` log prefix) appear in the same output bundle.
   **Q5 from the architecture doc is resolved: `extraNodeModules` is
   sufficient.** Keep the `resolveRequest` fallback as belt-and-suspenders.

2. **Tag map for the basic-app shape.** `<div>` -> `View`, `<h1>` -> `Text`,
   `<button>` -> `Pressable` + nested `<Text>`. No bundle modification needed.

3. **TypeScript + expo-doctor.** `npx tsc --noEmit` is clean. `npx expo-doctor`
   is 18/18 with no warnings after pinning `react-native@0.76.9` and adding
   the `expo-asset` peer.

4. **Hermes + New Architecture.** Both enabled in `app.json` per D8; bundler
   accepts them without complaint.

### Open issues uncovered

1. **`__getLocalStorage` async vs sync.** Web's runtime uses synchronous
   `localStorage`; native must use async `SecureStore`. The spike's runtime
   exposes the storage helpers as async, but the compiled Jac code may call
   them synchronously. Real impact won't show until we run an auth flow.
   **Action for R1/R3:** decide whether to (a) change the storage contract to
   async on both platforms or (b) cache hot keys (e.g. `jac_token`) in an
   in-memory mirror so the sync API still works on native.

2. **HTML attribute names in the bundle.** The compiled output emits
   `{"class": "app", "data-id": "button"}` verbatim. RN ignores these but
   warns about unknown DOM props in dev. We filter them in `adaptProps()`;
   long-term this is better handled at compile time when the target is
   `react-native` (saves bytes and silences warnings).

3. **Web-only imports in `client_runtime.cl.jac`.** The current runtime hard
   imports `react-dom/client`, `react-router-dom`, `react-error-boundary`,
   `react-hook-form`, `@hookform/resolvers/zod`, `zod`. None of those should
   be in the native bundle at all. **This is the R3 motivation** - the
   renderer + the runtime need to be target-aware, not pulled from one file.

4. **`_entry.js` is web-only.** It calls `createRoot` +
   `document.getElementById("root")`. **R2 motivation confirmed**: entry
   generation must be per-target. Our `index.ts` is what the native generator
   should emit.

5. **Emulator/device verification not run here.** This spike was validated up
   to "Metro bundles cleanly with all the right symbols in the output." It
   does **not** prove the bundle runs on a device - `<View>` rendering with
   our adapted props, `fetch` against `10.0.2.2`, and SecureStore behavior
   all need a human with an emulator. The bundling story being green is the
   highest-risk gate; the runtime APIs we lean on (`View`, `Text`,
   `Pressable`, `fetch`, `SecureStore`) are RN basics with well-understood
   behavior.

### Tag-map gaps to flag in R3

Things the basic-app fixture does NOT exercise but the documented tag map
covers (D10), and which will need a fuller fixture in Phase 1:

- `<input>` / `<textarea>` -> `TextInput`. `onChange` -> `onChangeText`
  translation is in `adaptProps()` but untested.
- `<a href="...">` -> `Text` + `Linking.openURL`. Untested.
- `<img>` -> `Image`. Untested.
- `<ul>`/`<ol>`/`<li>` -> `View` (no list semantics). Untested.
- Unmapped tag fallback -> `View` with red dashed border in `__DEV__`.
  Implemented + warns once per tag; verify visually in Phase 1 fixture.

### What stays out of scope

- Router (`Router`, `Routes`, `Route`, `Link`, `useNavigate`) - exported as
  `throw new Error(...)` stubs so any unintended usage is loud.
- Forms (`JacForm`, `useJacForm`) - stubs.
- Auth (`jacSignup`, `jacLogin`, etc.) - stubs.
- Caching layer - `__cachedEndpointCall` is a passthrough; the spike calls
  walkers directly.
- iOS - Android only.
- Fast Refresh / dev loop - Phase 2.

---

## Recommendation: GO

The two Phase 0 risks the doc named - *"can Metro consume an already-compiled
Jac bundle"* and *"can a runtime adapter swap React DOM for React Native
without modifying the bundle"* - are both answered yes by the Metro export
above. The remaining risks (storage contract, attribute filtering, web-only
imports in `client_runtime.cl.jac`) are exactly what refactors R1/R2/R3 are
designed to address, and Phase 0 surfaced them at the right level of detail
to make those refactors targeted instead of speculative.

**Next slice:** plan and implement R1 + R2 + R3 from the architecture doc.
Suggested order: R2 (smallest, lowest risk, unblocks native entry generator)
-> R3 (renderer dispatch, swap our hand-written runtime in via the contract)
-> R1 (split `ViteCompiler` so the RN target can drive `JacClientCompiler`
without Vite). Each refactor lands behind the existing test gate per D4.
