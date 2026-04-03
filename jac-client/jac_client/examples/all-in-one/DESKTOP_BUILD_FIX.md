# Desktop Build Fix Documentation

## Problem Summary

The macOS desktop build had critical issues preventing the app from launching:

### Initial Issues
1. **"No bytecode found" Error**: App crashed on launch with `ImportError: No bytecode found for {file_path}`
2. **Massive Installer Size**: DMG was 2.4GB (too large for distribution)
3. **PyInstaller Bundling Failure**: `.jir` bytecode files weren't being bundled correctly
4. **macOS Compatibility**: System library linking issues on macOS 26.3.1 beta

## Root Causes

### 1. PyInstaller Bytecode Bundling Bug
**Location**: `desktop_target.impl.jac` (line ~2950)

**Problem**:
```python
# OLD (WRONG):
rel_path = item.relative_to(jaclang_path)
# This stripped the 'jaclang/' prefix!
```

**Impact**: The `jaclang/_precompiled/*.jir` bytecode files were bundled to wrong paths, causing runtime import failures.

### 2. Missing Runtime Hook
PyInstaller frozen apps need special handling to locate bundled bytecode files.

### 3. macOS 26.3.1 Compatibility
The beta macOS version doesn't have `/usr/lib/libSystem.B.dylib` as a file (it's in dyld cache), breaking PyInstaller's onefile mode.

### 4. File Detection Logic Bug
**Location**: `desktop_target.impl.jac` (line ~2796)

**Problem**:
```python
# OLD (WRONG):
if not bundled_binary.exists():  # Returns True for directories!
```

**Impact**: Code couldn't detect onedir mode properly.

## Fixes Applied

### Fix 1: Corrected Bytecode Bundling Path
**File**: `jac-client/jac_client/plugin/src/targets/impl/desktop_target.impl.jac`

**Change** (line ~2950):
```python
# BEFORE:
rel_path = item.relative_to(jaclang_path)
datas.append((str(item), str(rel_path.parent)))

# AFTER:
rel_path = item.relative_to(jaclang_path.parent)  # Keep 'jaclang/' prefix
datas.append((str(item), str(rel_path.parent)))
```

### Fix 2: Added Runtime Hook
**File**: `src-tauri/runtime_hook_jaclang.py` (auto-generated)

```python
if getattr(sys, 'frozen', False) and hasattr(sys, '_MEIPASS'):
    jaclang_path = Path(sys._MEIPASS) / 'jaclang'
    os.environ['JACLANG_BUNDLE_PATH'] = str(jaclang_path)
    os.environ['JACLANG_PRECOMPILED_PATH'] = str(jaclang_path / '_precompiled')
```

### Fix 3: Optimized PyInstaller Excludes
**File**: `desktop_target.impl.jac` (line ~3003)

```python
excludes=[
    'tkinter', 'matplotlib', 'numpy', 'pandas', 'scipy', 'pkg_resources',
    'pytest', 'test', 'tests', 'testing',
    'IPython', 'jupyter', 'notebook',
    'PIL', 'Pillow', 'cv2', 'opencv',
]
```

**Impact**: Reduced bundle size significantly.

### Fix 4: Wrapper Script Mode (Final Solution)
**File**: `src-tauri/binaries/jac-sidecar`

Due to macOS 26.3.1 beta incompatibility with PyInstaller's onefile mode and Tauri's issues with onedir mode, we implemented a **wrapper script approach**:

```bash
#!/bin/bash
# Finds system Python and runs sidecar using installed jaclang
PYTHON=""
for py in python3 python /usr/local/bin/python3 /opt/homebrew/bin/python3; do
    if command -v "$py" &> /dev/null; then
        PYTHON="$py"
        break
    fi
done

exec $PYTHON -m jac_client.plugin.src.targets.desktop.sidecar.main \
    --module-path "$JAC_DIR/main.jac" \
    --base-path "$JAC_DIR" \
    "$@"
```

**Benefits**:
- ✅ Works on macOS 26.3.1 beta
- ✅ Tiny DMG size: 3.3 MB (vs 2.4 GB)
- ✅ Uses system Python + jaclang (no bundling issues)
- ✅ Easier debugging and updates

**Trade-off**: Requires Python + jaclang installed on user machine.

### Fix 5: Fixed File Detection Logic
**File**: `desktop_target.impl.jac` (line ~2796)

```python
# BEFORE:
if not bundled_binary.exists():  # Bug: directories return True

# AFTER:
if not bundled_binary.is_file():  # Correct: checks if it's a file
```

## How to Build

### Prerequisites
```bash
# Ensure you're in the conda environment
conda activate jac-dev

# Verify installations
python --version  # Should be 3.12+
jac --version
```

### Clean Build
```bash
cd /path/to/jaseci/jac-client/jac_client/examples/all-in-one

# Clean all build artifacts
rm -rf src-tauri/binaries/* src-tauri/target/release/bundle src-tauri/dist src-tauri/build .jac/cache

# Build desktop app
jac build main.jac --client desktop
```

### Output
```
✔ Desktop app built successfully!
  Output: src-tauri/target/release/bundle/dmg/all-in-one_1.0.0_aarch64.dmg
  Size: ~3.3 MB
```

## How to Install & Run

### Installation
```bash
# 1. Open the DMG
open src-tauri/target/release/bundle/dmg/all-in-one_1.0.0_aarch64.dmg

# 2. Drag app to Applications folder

# 3. (Optional) Delete old version first
rm -rf /Applications/all-in-one.app
```

### Running the App

**Important**: The wrapper mode requires Python + jaclang to be available.

#### Method 1: Run from Terminal (Recommended for Development)
```bash
# Activate conda environment (so wrapper finds Python + jaclang)
conda activate jac-dev

# Run the app
/Applications/all-in-one.app/Contents/MacOS/all-in-one
```

**Expected Output**:
```
[sidecar] JAC_SIDECAR_PORT=58799
Sidecar started on http://127.0.0.1:58799
Injecting API base URL: http://127.0.0.1:58799
```

#### Method 2: Double-Click (For End Users)
```bash
# For end users, ensure Python + jaclang are in system PATH
# Install dependencies globally:
pip install jaclang jac-scale byllm jac-coder

# Then double-click the app in Applications
```

## Verification

### 1. Check Sidecar Started
After launching, you should see in terminal:
```
[sidecar] JAC_SIDECAR_PORT=XXXXX
Sidecar started on http://127.0.0.1:XXXXX
```

### 2. Debug Panel Check
1. Click **"Debug"** button in app
2. Verify:
   - ✅ `__JAC_API_BASE_URL__`: Shows URL (e.g., `http://127.0.0.1:58799`)
   - ✅ `Tauri Available`: Shows "Yes"
   - ✅ **Test Walker Ping** button works

### 3. Test Features
- Try **Sign Up** / **Login**
- Navigate to different pages
- Check that API calls work

## Troubleshooting

### Issue: "Sidecar not found in resources"
**Cause**: Old app still installed

**Solution**:
```bash
rm -rf /Applications/all-in-one.app
# Then reinstall from the NEW DMG
```

### Issue: "Python not found" or "jaclang not installed"
**Cause**: Wrapper can't find Python or jaclang

**Solution**:
```bash
# Activate conda environment before running
conda activate jac-dev
/Applications/all-in-one.app/Contents/MacOS/all-in-one

# OR install globally:
pip install jaclang jac-scale byllm jac-coder
```

### Issue: API URL shows "(not set)"
**Cause**: Sidecar failed to start

**Solution**:
```bash
# Run from terminal to see error messages
conda activate jac-dev
/Applications/all-in-one.app/Contents/MacOS/all-in-one 2>&1 | grep -A 10 "Error\|sidecar"
```

### Issue: Port conflicts
**Cause**: Another app using the port

**Solution**: The sidecar uses `--port 0` (auto-assign), so this rarely happens. If it does:
```bash
# Check what's using ports
lsof -i :8000
# Kill if needed
kill -9 <PID>
```

## Files Modified

### Core Fixes
- `jac-client/jac_client/plugin/src/targets/impl/desktop_target.impl.jac`
  - Lines ~2950: Fixed bytecode bundling path
  - Lines ~2796: Fixed file detection logic
  - Lines ~2760: Added dist/build cleanup
  - Lines ~3003: Optimized excludes
  - Lines ~2014: Added onedir directory detection
  - Lines ~2070: Added glob pattern for directories

### Generated Files (Auto-created)
- `src-tauri/jac-sidecar.spec`: PyInstaller spec with fixes
- `src-tauri/runtime_hook_jaclang.py`: Runtime hook for bytecode resolution
- `src-tauri/binaries/jac-sidecar`: Wrapper script (final solution)
- `src-tauri/tauri.conf.json`: Updated resources config

## Production Deployment

### For Distribution to End Users

**Option 1: Include Python in DMG (Larger)**
- Bundle Python.org Python installer alongside app
- Provide install script that sets up Python + jaclang

**Option 2: Require Python (Current Approach)**
- Document Python + jaclang as prerequisites
- Provide installation instructions:
  ```bash
  # Install Homebrew (if not installed)
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Install Python
  brew install python3

  # Install jaclang
  pip3 install jaclang jac-scale byllm jac-coder
  ```

**Option 3: Wait for macOS Stable Release**
- Once you're on a stable macOS (not 26.x beta), PyInstaller onefile mode should work
- This will create a truly standalone binary

## Known Limitations

1. **Requires Python + jaclang**: Users must have these installed (not truly standalone)
2. **macOS 26.3.1 Beta Only**: The libSystem.B.dylib issue is specific to this beta version
3. **First Launch Slower**: JAC compiles `.jac` files on first run (no precompiled bytecode)

## Future Improvements

1. **Fix PyInstaller for Stable macOS**: Once on stable macOS, revert to onefile bundling
2. **Add Python Check on Launch**: Show friendly error if Python/jaclang missing
3. **Auto-install Script**: Create installer that sets up Python + dependencies
4. **CI/CD Integration**: Automate builds on stable macOS via GitHub Actions

## Summary

**Before**: 2.4GB DMG, crashes on launch, "No bytecode found" error

**After**: 3.3MB DMG, works perfectly, sidecar starts successfully

**Key Achievement**: Desktop app now fully functional on macOS 26.3.1 beta using wrapper mode!
