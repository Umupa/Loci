import { defineConfig } from "vitest/config";

// A probe that sends real prompts through a signed-in agent CLI. It is run by
// hand, one turn at a time, and is not part of `npm test`.
export default defineConfig({
  test: {
    environment: "happy-dom",
    include: ["scripts/acceptance/learn/*.probe.ts"],
    fileParallelism: false,
    testTimeout: 90 * 60_000,
    hookTimeout: 60_000,
    server: { deps: { inline: ["@excalidraw/excalidraw"] } },
  },
});
