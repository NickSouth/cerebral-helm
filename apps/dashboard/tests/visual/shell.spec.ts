import { test, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

/**
 * The three-zone dashboard shell (NIC-53) is the canonical visual fixture. The bootstrap
 * fixture is fully static (fixed clocks, no randomness) so screenshots are deterministic.
 */

const VIEWPORTS = [
  { name: "compact", width: 1280, height: 900 },
  { name: "laptop", width: 1512, height: 982 },
  { name: "external", width: 1920, height: 1200 }
] as const;

for (const viewport of VIEWPORTS) {
  test(`dashboard shell is stable at ${viewport.name} width`, async ({ page }) => {
    await page.setViewportSize({ width: viewport.width, height: viewport.height });
    await page.goto("/");
    await expect(page.getByRole("region", { name: "Heimlich" })).toBeVisible();
    // The bottom-bar clock is live wall-time; mask it so the deterministic baseline never flakes.
    await expect(page).toHaveScreenshot(`shell-${viewport.name}.png`, {
      fullPage: true,
      mask: [page.locator(".bottom-bar__clock")]
    });
  });
}

test("dashboard shell is stable under reduced motion", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.setViewportSize({ width: 1512, height: 982 });
  await page.goto("/");
  await expect(page.getByRole("region", { name: "Heimlich" })).toBeVisible();
  await expect(page).toHaveScreenshot("shell-reduced-motion.png", {
    fullPage: true,
    mask: [page.locator(".bottom-bar__clock")]
  });
});

test("dashboard shell has no critical or serious accessibility violations", async ({ page }) => {
  await page.goto("/");
  await page.getByRole("region", { name: "Heimlich" }).waitFor();

  const results = await new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa"]).analyze();

  const blocking = results.violations.filter(
    (violation) => violation.impact === "critical" || violation.impact === "serious"
  );

  expect(blocking, JSON.stringify(blocking.map((v) => v.id), null, 2)).toEqual([]);
});
