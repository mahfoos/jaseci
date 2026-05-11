# Mobile CI/CD

This document describes the native mobile build pipeline for Jac apps and
what remains to be set up for iOS support.

## Overview

The workflow at `.github/workflows/build-mobile.yml` builds mobile apps
**directly on the GitHub Actions runner**. This mirrors the desktop
pipeline (`build-standalone.yml`, `build-protomcp-audit.yml`) which
compiles Tauri/Cargo locally on the runner and uploads the installer as
a GitHub artifact.

| Platform | Runner | Status |
|---|---|---|
| Android | `ubuntu-latest` | Implemented — produces signed release APK |
| iOS | `macos-latest` | Pending — needs Apple Developer credentials (see below) |

## How the Android build works

1. **Provision the runner** — JDK 17, Android SDK, Python 3.12, Node 20, Yarn.
2. **Install Jac packages** — `pip install -e jac` and `pip install -e jac-client` from the checkout.
3. **`jac setup mobile`** — idempotent. Skipped if `mobile/` already exists.
4. **`jac build --client mobile -p android -b preview`** — prepares the web
   bundle, copies it into `.jac/mobile/assets/jac-app/`, and installs
   `node_modules` in `.jac/mobile/`.
5. **`npx expo prebuild --platform android --clean --no-install`** —
   generates the native `android/` Gradle project from `app.json` + `package.json`.
6. **Configure release signing** — auto-generates a throwaway keystore via
   `keytool` if no real signing secrets are configured; uses real secrets
   if present. Patches `android/app/build.gradle` to wire the keystore
   into the `release` signing config.
7. **`./gradlew assembleRelease`** — produces a signed release APK
   (pre-bundled JS, `__DEV__ = false`, installable on any device).
8. **Upload artifact** — APK is attached to the workflow run, downloadable
   from the Actions tab.

### Triggers

- **Push to `feature/mobile-cicd-pipeline`** when this workflow file or any
  file under `jac-client/` changes.
- **Manual `workflow_dispatch`** with an optional `app_path` input
  (defaults to `jac-client/jac_client/examples/all-in-one`).

### Signing modes

The workflow always produces a release-mode APK. The signing keystore
is chosen at runtime:

| Keystore source | When used | APK is… |
|---|---|---|
| Real keystore from repository secrets | All four `ANDROID_*` secrets are configured | Stable signing identity. **Play-Store-distributable.** |
| Auto-generated throwaway keystore | Any of the four secrets is missing | Installable on any device for QA / sideload. **Cannot be uploaded to Google Play** — the signing identity changes every CI run, which breaks Play's update verification. |

To produce a Play-Store-ready APK, generate a keystore and store it as
GitHub secrets.

## Generating a stable release keystore

Do this **once**, locally, and **back up the resulting `.keystore` file
somewhere safe**. If you lose it, you cannot publish updates to your app
on the Play Store ever again — Google does not allow re-signing.

```bash
# 1. Generate a release keystore (do this once, locally, and back it up)
keytool -genkeypair -v \
  -keystore release.keystore \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias <YOUR_KEY_ALIAS>

# 2. Base64-encode for GitHub secret storage
base64 -i release.keystore | pbcopy    # macOS
# or
base64 release.keystore | xclip -sel clip   # Linux
```

Add the following GitHub repository secrets (Settings → Secrets and
variables → Actions):

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | The base64 output above |
| `ANDROID_KEYSTORE_PASSWORD` | The keystore password you set |
| `ANDROID_KEY_ALIAS` | The alias you passed to `-alias` |
| `ANDROID_KEY_PASSWORD` | The key password (often the same as keystore password) |

The next workflow run will detect all four secrets and sign with your
keystore automatically. The build summary will say
`Signing: release-keystore` instead of `throwaway-keystore`.

## Upgrading from APK to AAB (Google Play)

Google Play requires `.aab` (Android App Bundle), not `.apk`. To produce
an AAB instead, change the gradle command in
`.github/workflows/build-mobile.yml`:

```yaml
./gradlew bundleRelease   # instead of assembleRelease
```

The output path changes too:
`app/build/outputs/bundle/release/app-release.aab`.

You may want to keep both an APK (for sideload testing) and an AAB (for
Play upload) — that requires two gradle invocations.

---

## Local development

You don't need CI for day-to-day work. Three local workflows depending on
what you're doing:

### 1. Fast iteration with HMR (most common)

```bash
cd jac-client/jac_client/examples/all-in-one
jac start main.jac --client mobile --dev
```

- Runs Vite dev server on `:5173` + backend on `:8000` + Expo dev server.
- Scan the QR code with the **Expo Go** app on your phone (same Wi-Fi).
- Edit `.jac` / `.tsx` files → live reload, no rebuild.
- This is what you'll use 90% of the time.

### 2. Test the bundled app on device (no HMR)

```bash
jac start main.jac --client mobile
```

- Same as above but loads the pre-built bundle instead of the Vite dev
  server. Useful to verify the bundling step before pushing to CI.
- Still uses Expo Go on your phone.

### 3. Build a real APK locally (mirrors what CI does)

Prerequisites (one-time setup):

- **JDK 17** — `brew install --cask temurin@17` on macOS,
  `sudo apt install openjdk-17-jdk` on Ubuntu.
- **Android SDK** — easiest path: install Android Studio, then export:
  ```bash
  export ANDROID_HOME="$HOME/Library/Android/sdk"   # macOS default
  export PATH="$PATH:$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin"
  ```
- **Node 20 + Yarn**.

Then:

```bash
cd jac-client/jac_client/examples/all-in-one

# 1. Prepare the bundle (re-run after code changes)
jac build --client mobile -p android -b preview

# 2. Generate the native android/ project
cd .jac/mobile
npx expo prebuild --platform android --clean --no-install

# 3. Build a debug APK (no keystore needed)
cd android
./gradlew assembleDebug
# Output: app/build/outputs/apk/debug/app-debug.apk
```

Install on a connected device with `adb`:

```bash
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

> **Debug APK caveat:** `assembleDebug` does not pre-bundle the JS and
> assumes a Metro bundler is running on your laptop. For a self-contained
> APK that behaves like CI's output, use the release build below.

#### Release build locally (matches CI output)

```bash
cd .jac/mobile/android

# Generate a throwaway keystore (one-time, per .jac/mobile/)
keytool -genkeypair -v \
  -keystore app/release.keystore \
  -storepass ciinstall -keypass ciinstall -alias ciinstallkey \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -dname "CN=Local Dev, O=Me, C=US"

# Append signing config so the patched build.gradle picks it up
cat >> gradle.properties <<'EOF'
MYAPP_RELEASE_STORE_FILE=release.keystore
MYAPP_RELEASE_STORE_PASSWORD=ciinstall
MYAPP_RELEASE_KEY_ALIAS=ciinstallkey
MYAPP_RELEASE_KEY_PASSWORD=ciinstall
EOF

./gradlew assembleRelease
# Output: app/build/outputs/apk/release/app-release.apk
```

You only need the keystore + properties dance once per `.jac/mobile/` —
it'll persist until you re-run `expo prebuild --clean`.

### iOS locally (Mac only)

```bash
jac build --client mobile -p ios -b preview
cd .jac/mobile
npx expo prebuild --platform ios --clean --no-install
cd ios && pod install
open *.xcworkspace   # opens Xcode
# In Xcode: pick a simulator → ▶ Run, or pick your device with signing identity
```

For CLI-only:
`xcodebuild -workspace *.xcworkspace -scheme <Name> -configuration Debug build`.
For first-time setup Xcode is much easier — let it auto-create the
signing identity and then drop to CLI later.

---

## iOS — what remains to be set up

iOS cannot be built on Linux runners; Xcode only runs on macOS. The plan
is to add a sibling `build-ios` job in the same workflow that runs on
`macos-latest` once the Apple-side credentials are in place.

### 1. Apple Developer Program membership

- Cost: **$99/year** (individual) or **$299/year** (organization/company).
- Sign up at https://developer.apple.com/programs/.
- For an organization, Apple requires a D-U-N-S number — that adds 1–2
  weeks of paperwork. Plan ahead.

### 2. App ID

In https://developer.apple.com/account/resources/identifiers/list, register
an App ID with bundle identifier matching `[mobile].bundle_id` in
`jac.toml`. For the all-in-one example this is `com.jaseci.allinone`.

### 3. Distribution certificate

The cert proves "Apple authorized this team to sign apps."

- Easiest path: open Xcode on a Mac, sign in with the Apple Developer
  account, let Xcode generate a Distribution certificate, then export it
  from Keychain Access as a `.p12` file with a password.
- Alternative: `fastlane match` to manage certs in a private git repo —
  recommended once you have more than one developer.

### 4. Provisioning profile

The profile binds together (cert) + (App ID) + (device list, for ad-hoc).

- For **Ad Hoc** (internal testing on specific UDID-registered devices):
  download a `.mobileprovision` from developer.apple.com.
- For **App Store / TestFlight**: download the "App Store" profile.

### 5. App Store Connect API key *(only if CI should auto-upload to TestFlight)*

- Go to https://appstoreconnect.apple.com → Users and Access → Keys.
- Create a new API key with "App Manager" role.
- Download the `.p8` file (only available once — save it).
- Note the **Key ID** and **Issuer ID** shown on that page.

Skip this if you'll upload to TestFlight manually via Transporter / Xcode.

### 6. Team ID

10-character string visible at the top-right of
https://developer.apple.com/account/ (the "Membership" page).

### GitHub secrets to add

| Secret | Source |
|---|---|
| `IOS_CERTIFICATE_BASE64` | `base64 -i Certificates.p12` |
| `IOS_CERTIFICATE_PASSWORD` | Password set when exporting the `.p12` |
| `IOS_PROVISIONING_PROFILE_BASE64` | `base64 -i profile.mobileprovision` |
| `IOS_TEAM_ID` | 10-char Team ID from step 6 |
| `IOS_APP_STORE_CONNECT_KEY_BASE64` | `base64 -i AuthKey_XXXX.p8` (optional) |
| `IOS_APP_STORE_CONNECT_KEY_ID` | Key ID from step 5 (optional) |
| `IOS_APP_STORE_CONNECT_ISSUER_ID` | Issuer ID from step 5 (optional) |

### Workflow changes needed

When the credentials are ready, add a `build-ios` job alongside `build-android`:

```yaml
build-ios:
  name: Build iOS
  runs-on: macos-latest
  timeout-minutes: 90
  steps:
    # ... same Python / Node / jac install steps as Android ...

    - name: Import signing certs
      uses: apple-actions/import-codesign-certs@v3
      with:
        p12-file-base64: ${{ secrets.IOS_CERTIFICATE_BASE64 }}
        p12-password: ${{ secrets.IOS_CERTIFICATE_PASSWORD }}

    - name: Install provisioning profile
      uses: apple-actions/download-provisioning-profiles@v3
      with:
        bundle-id: com.jaseci.allinone
        issuer-id: ${{ secrets.IOS_APP_STORE_CONNECT_ISSUER_ID }}
        api-key-id: ${{ secrets.IOS_APP_STORE_CONNECT_KEY_ID }}
        api-private-key: ${{ secrets.IOS_APP_STORE_CONNECT_KEY_BASE64 }}

    - name: Prepare mobile bundle
      working-directory: ${{ env.APP_PATH }}
      run: jac build --client mobile -p ios -b preview

    - name: Generate native iOS project
      working-directory: ${{ env.APP_PATH }}/.jac/mobile
      run: |
        npx expo prebuild --platform ios --clean --no-install
        cd ios && pod install

    - name: Build IPA
      working-directory: ${{ env.APP_PATH }}/.jac/mobile/ios
      run: |
        xcodebuild -workspace *.xcworkspace \
          -scheme <SchemeName> \
          -configuration Release \
          -archivePath build/App.xcarchive \
          archive
        xcodebuild -exportArchive \
          -archivePath build/App.xcarchive \
          -exportPath build/ \
          -exportOptionsPlist ExportOptions.plist

    - uses: actions/upload-artifact@v4
      with:
        name: ios-${{ github.run_number }}
        path: ${{ env.APP_PATH }}/.jac/mobile/ios/build/*.ipa
```

You'll also need an `ExportOptions.plist` checked into the repo or
generated on the fly — it tells `xcodebuild` whether to package for
Ad Hoc, Development, or App Store distribution.

### Cost note

`macos-latest` runners are billed at **10×** the per-minute rate of
`ubuntu-latest` on GitHub-hosted plans. A 30-minute iOS build counts as
300 ubuntu-minutes against your monthly allowance. If you're on the free
tier, this disappears fast. Options if it becomes a problem:

- Self-hosted Mac runner (one-time hardware cost, no per-minute fees).
- Only build iOS on tagged releases, not every push.
- Cache `Pods/`, `~/Library/Developer/Xcode/DerivedData`, and `node_modules`
  aggressively to shrink build time.

---

## Troubleshooting

**`jac --version` works locally but workflow fails to find it.**
The pip-installed entry points may not be on `PATH` in the next step.
Either invoke as `python -m jaclang` or ensure the `setup-python` step
exports its `Scripts` / `bin` to `GITHUB_PATH`.

**`expo prebuild` warns about plugins not installed.**
The `--no-install` flag we pass skips an extra `yarn install` because
`_prepare_build_dir` already ran one. If a plugin in `app.json` was added
after that step, you may need to drop `--no-install`.

**Gradle wrapper "Permission denied".**
The workflow runs `chmod +x ./gradlew` before invoking it. If you see this
on a self-hosted runner, the checkout may have lost the executable bit —
keep the `chmod`.

**APK installs but the WebView is blank.**
The web bundle was not embedded. Check that the `Verify build artifacts`
step found `assets/jac-app/bundle.ts`. If missing, `jac build --client
mobile` didn't run all four bundle steps — most likely cause is an
unrelated Python error earlier in that step that the shell swallowed
without failing the job.

**Release APK build fails complaining about missing signing config.**
The workflow's `Configure release signing` step patches
`android/app/build.gradle` to add a release signing config. If the regex
didn't match (because Expo's prebuild template changed shape), the patch
prints "Could not find signingConfigs block in build.gradle" and fails.
Inspect the generated `build.gradle` and adjust the regex in the workflow
to match the new structure.

**APK installs once but won't update next CI run.**
You're using the throwaway-keystore fallback. Each CI run generates a
fresh keystore, so Android sees a different signing identity and refuses
the update. Either uninstall the old APK before reinstalling, or
configure the four `ANDROID_*` secrets to use a stable keystore.
