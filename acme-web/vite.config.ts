import path from "node:path";

import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

import {
  NOSCRIPT_FALLBACK_STYLESHEET,
  renderNoscriptFallbackHtml,
} from "./src/landing/noscriptFallback.ts";

/**
 * The landing page must say something useful with JavaScript disabled — search
 * crawlers and privacy-hardened browsers both hit that path, and a blank page
 * is a lost visitor. This injects a static fallback at build time so it costs
 * the JS-enabled visitor nothing.
 *
 * Only the landing entry. The authenticated app has nothing to show a visitor
 * who cannot run it.
 */
function landingNoscriptFallback() {
  return {
    name: "landing-noscript-fallback",
    transformIndexHtml: {
      order: "pre" as const,
      handler(html: string, ctx: { filename: string }) {
        if (!ctx.filename.endsWith("landing.html")) return html;
        return html
          .replace("</head>", `<noscript><style>${NOSCRIPT_FALLBACK_STYLESHEET}</style></noscript></head>`)
          .replace("</body>", `<noscript>${renderNoscriptFallbackHtml()}</noscript></body>`);
      },
    },
  };
}

export default defineConfig({
  plugins: [react(), landingNoscriptFallback()],

  // Reads the `paths` in tsconfig.app.json, so the @/ alias is declared
  // once instead of being repeated here and in vitest.config.ts.
  resolve: { tsconfigPaths: true },

  build: {
    rollupOptions: {
      input: {
        // Two entries, two bundles, one container. `app` is the authenticated
        // SPA at app.<domain>; `landing` is the public page at the apex. The
        // web image serves whichever matches the Host, so both ship in one
        // deploy — and nothing the app imports can reach the landing bundle.
        app: path.resolve(import.meta.dirname, "index.html"),
        landing: path.resolve(import.meta.dirname, "landing.html"),
      },
    },
  },

  server: {
    port: 3000,
    // Off unless asked for. Every e2e spec mocks with page.route, so the dev
    // server does not need a backend; the proxy exists for manual work against
    // a live BFF, where the refresh cookie requires a single origin.
    proxy: process.env.DEV_API_PROXY
      ? { "/api": { target: process.env.DEV_API_PROXY, changeOrigin: false } }
      : undefined,
  },
});
