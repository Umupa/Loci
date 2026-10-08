import { defineConfig } from "vitest/config";

// Isolated failure-injection and event-stress contracts. Regressions fail
// normally rather than being skipped or marked as expected failures.
export default defineConfig({
  test: {
    environment: "happy-dom",
    include: ["scripts/acceptance/stability/*.test.ts"],
    fileParallelism: false,
    testTimeout: 30_000,
  },
});
