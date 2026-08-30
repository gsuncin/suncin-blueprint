import path from "node:path";

import { defineConfig } from "vitest/config";

export default defineConfig({
  // Declared explicitly rather than read from tsconfig, as vite.config.ts
  // does. Vitest 3 ships its own Vite types, which predate Vite 8's native
  // `resolve.tsconfigPaths` — so this is the one place the alias is
  // repeated. Keep it in step with the `paths` in tsconfig.app.json.
  resolve: {
    alias: { "@": path.resolve(import.meta.dirname, "./src") },
  },
  test: {
    environment: "jsdom",
    setupFiles: ["./src/test/setup.ts"],
    // Playwright specs are not Vitest specs; without this, `test:unit` tries to
    // run them and fails in a way that looks like a broken component.
    exclude: ["tests/e2e/**", "node_modules/**", "dist/**"],
    // Injected here rather than read from a .env file, so the suite does not
    // depend on a developer's local environment to pass.
    env: {
      VITE_API_URL: "http://127.0.0.1:3000/api",
    },
    coverage: {
      provider: "v8",
      reporter: ["text", "html"],
      exclude: ["**/*.test.{ts,tsx}", "src/test/**", "dist/**"],
    },
  },
});
