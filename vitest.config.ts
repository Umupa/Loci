import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    environment: "node",
    include: ["src/**/*.test.ts", "scripts/*.test.ts", "scripts/e2e/*.test.ts", "scripts/eval/*.test.ts"],
    server: { deps: { inline: ["@excalidraw/excalidraw"] } },
  },
});
