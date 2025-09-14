import { sveltekit } from "@sveltejs/kit/vite";
import { defineConfig } from "vite";
import fs from "fs";
import path from "path";

const crossOriginHeadersPlugin = {
  name: "cross-origin-headers-plugin",
  configureServer(server) {
    server.middlewares.use((req, res, next) => {
      res.setHeader("Cross-Origin-Opener-Policy", "same-origin");
      res.setHeader("Cross-Origin-Embedder-Policy", "require-corp");
      next();
    });
  },
};

const tfheWasmRedirectPlugin = {
  name: "tfhe-wasm-redirect-plugin",
  configureServer(server) {
    server.middlewares.use((req, res, next) => {
      if (req.url === "/node_modules/.vite/deps/tfhe_bg.wasm") {
        const wasmPath = path.resolve("node_modules/tfhe/tfhe_bg.wasm");

        if (fs.existsSync(wasmPath)) {
          res.setHeader("Content-Type", "application/wasm");
          const wasmBuffer = fs.readFileSync(wasmPath);
          res.end(wasmBuffer);
          return;
        }
      }
      next();
    });
  },
};

export default defineConfig({
    plugins: [
        crossOriginHeadersPlugin,
        sveltekit()
    ],
    optimizeDeps: {
        exclude: [
            "tfhe",
            "tfhe_bg.wasm"
        ]
    }
});
