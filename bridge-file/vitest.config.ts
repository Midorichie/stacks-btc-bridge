import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    // Use the Clarinet environment (provided by vitest-environment-clarinet)
    environment: 'clarinet',
    globals: true,
    // Point to a setup file that ensures __vitest_config__.coverage is defined
    setupFiles: ['./vitest.setup.ts'],
    // Even if coverage is disabled, we explicitly define it here.
    coverage: {
      enabled: false,         // Disable coverage to avoid triggering coverage-related errors
      provider: 'v8',         // (Optional) Specify the provider, e.g. "v8" or "c8"
      reporter: [],           // No reporters since coverage is disabled
      coverageFilename: 'coverage.json', // This value will be injected by our setup if missing
    },
  },
});
