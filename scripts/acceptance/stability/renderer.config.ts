import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import { fileURLToPath } from "node:url";

export default defineConfig({
  plugins: [react(), tailwindcss()],
  build: {
    outDir: "output/stability/renderer",
    rollupOptions: { input: fileURLToPath(new URL("./renderer.html", import.meta.url)) },
  },
  preview: { host: "127.0.0.1", port: 1439, strictPort: true },
});
