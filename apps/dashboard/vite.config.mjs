import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

export default defineConfig({
  plugins: [react()],
  test: {
    environment: "jsdom",
    globals: true,
    setupFiles: "./src/test/setup.ts",
    // Unit tests live in src. The Playwright visual specs under tests/visual run on
    // their own runner (test:visual) and must not be collected by Vitest.
    include: ["src/**/*.test.{ts,tsx}"]
  }
});
