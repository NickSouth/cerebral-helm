/*
 * Exit 0 if the Playwright browsers needed by the visual-regression guardrail are
 * installed, non-zero otherwise. The root test runner uses this to skip the visual
 * suite gracefully on machines/CI without browser binaries, rather than hard-failing.
 */
import { existsSync } from "node:fs";
import { chromium, webkit } from "@playwright/test";

try {
  const installed = [chromium, webkit].every((browser) => {
    try {
      return existsSync(browser.executablePath());
    } catch {
      return false;
    }
  });
  process.exit(installed ? 0 : 1);
} catch {
  process.exit(1);
}
