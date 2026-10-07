import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import type { Plugin } from "vite";
import { cpSync, createReadStream, existsSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { join, normalize } from "node:path";

// pdf.js fetches character maps, fallback fonts and image decoders by name at
// run time, so they are served as plain files under /pdfjs/ instead of bundled.
const PDFJS_ASSET_DIRS = ["cmaps", "standard_fonts", "wasm", "iccs"];
function pdfjsAssets(): Plugin {
  const source = fileURLToPath(new URL("./node_modules/pdfjs-dist/", import.meta.url));
  let outDir = "dist";
  return {
    name: "loci-pdfjs-assets",
    configResolved(config) {
      outDir = config.build.outDir;
    },
    configureServer(server) {
      server.middlewares.use("/pdfjs", (request, response, next) => {
        const relative = normalize(decodeURIComponent((request.url ?? "").split("?")[0])).replace(/^[/\\]+/, "");
        const file = join(source, relative);
        if (!PDFJS_ASSET_DIRS.includes(relative.split(/[/\\]/)[0]) || !existsSync(file) || !statSync(file).isFile()) {
          next();
          return;
        }
        response.setHeader("Content-Type", file.endsWith(".js") ? "text/javascript" : "application/octet-stream");
        createReadStream(file).pipe(response);
      });
    },
    closeBundle() {
      for (const dir of PDFJS_ASSET_DIRS) cpSync(join(source, dir), join(outDir, "pdfjs", dir), { recursive: true });
    },
  };
}

// @ts-expect-error process is a nodejs global
const host = process.env.TAURI_DEV_HOST;

export default defineConfig(async ({ mode }) => {
  const stable = mode === "stable";

  return {
    plugins: [react(), tailwindcss(), pdfjsAssets()],
    clearScreen: false,
    server: {
      port: 1420,
      strictPort: true,
      host: host || false,
      hmr: stable
        ? false
        : host
          ? {
              protocol: "ws",
              host,
              port: 1421,
            }
          : undefined,
      watch: {
        ignored: stable ? ["**/*"] : ["**/src-tauri/**"],
      },
    },
  };
});
