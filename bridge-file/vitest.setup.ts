// This setup file ensures that the global Vitest config object has a coverage property
if (!globalThis.__vitest_config__) {
  globalThis.__vitest_config__ = {};
}
if (!globalThis.__vitest_config__.coverage) {
  // Define a default coverage configuration to avoid errors in vitest-environment-clarinet
  globalThis.__vitest_config__.coverage = {
    coverageFilename: 'coverage.json',
  };
}
