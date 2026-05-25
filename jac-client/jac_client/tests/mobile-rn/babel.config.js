// jac-client: scaffold-managed; remove this line to opt out of auto-refresh
module.exports = function (api) {
  api.cache(true);
  return {
    presets: ['babel-preset-expo'],
  };
};
