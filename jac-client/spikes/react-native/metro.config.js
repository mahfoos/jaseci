// Learn more: https://docs.expo.dev/guides/customizing-metro/
const { getDefaultConfig } = require('expo/metro-config');
const path = require('path');

const projectRoot = __dirname;
const jacCompiledDir = path.resolve(projectRoot, 'jac-compiled');

const config = getDefaultConfig(projectRoot);

// Watch the compiled Jac bundle so edits there hot-reload.
config.watchFolders = [...(config.watchFolders ?? []), jacCompiledDir];

// Resolve `@jac/runtime` to our hand-written native runtime. Metro's
// `extraNodeModules` is checked when a normal node_modules lookup misses,
// which matches how the compiled bundle imports the package.
//
// Q5 in REACT_NATIVE_ARCHITECTURE.md: this is the first thing the spike
// validates. If deep imports like `@jac/runtime/something` show up later we
// will likely need a `resolver.resolveRequest` override instead.
const nativeRuntime = path.resolve(projectRoot, 'native_runtime.ts');
config.resolver.extraNodeModules = {
  ...(config.resolver.extraNodeModules ?? {}),
  '@jac/runtime': nativeRuntime,
};

// Belt-and-suspenders: a resolveRequest hook for the bare specifier. This
// catches the case where `extraNodeModules` doesn't kick in (depends on the
// Metro version's resolver order).
const defaultResolveRequest = config.resolver.resolveRequest;
config.resolver.resolveRequest = (context, moduleName, platform) => {
  if (moduleName === '@jac/runtime') {
    return {
      filePath: nativeRuntime,
      type: 'sourceFile',
    };
  }
  if (defaultResolveRequest) {
    return defaultResolveRequest(context, moduleName, platform);
  }
  return context.resolveRequest(context, moduleName, platform);
};

module.exports = config;
