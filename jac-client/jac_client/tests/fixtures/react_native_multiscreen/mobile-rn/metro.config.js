// jac-client: scaffold-managed; remove this line to opt out of auto-refresh
const { getDefaultConfig } = require('expo/metro-config');
const path = require('path');

const projectRoot = __dirname;
const compiledDir = path.resolve(projectRoot, '../.jac/client/compiled');

const config = getDefaultConfig(projectRoot);

// Watch the Jac-compiled JS bundle so edits to .cl.jac files
// trigger Metro Fast Refresh once `jac start --dev` (Phase 2) is wired up.
config.watchFolders = [...(config.watchFolders || []), compiledDir];

// Alias `@jac/runtime` -> compiled/client_runtime.js so the bundle's
// import resolves to the native runtime that ReactNativeTarget.build wrote.
config.resolver = config.resolver || {};
config.resolver.extraNodeModules = {
  ...(config.resolver.extraNodeModules || {}),
  '@jac/runtime': path.resolve(compiledDir, 'client_runtime.js'),
};
// Without ``nodeModulesPaths`` set explicitly Metro fails to resolve
// React etc. from the aliased dir because they live in the Expo
// project's node_modules, not in .jac/client/compiled.
config.resolver.nodeModulesPaths = [
  path.resolve(projectRoot, 'node_modules'),
  ...(config.resolver.nodeModulesPaths || []),
];

module.exports = config;
