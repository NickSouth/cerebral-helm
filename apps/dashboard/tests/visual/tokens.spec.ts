import { test, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

/**
 * The token reference page (App.tsx) is the first canonical visual fixture. It is
 * fully static — no clock, no randomness — so screenshots are deterministic.
 */

const VIEWPORTS = [
  { name: "compact", width: 1280, height: 900 },
  { name: "laptop", width: 1512, height: 982 },
  { name: "external", width: 1920, height: 1200 }
] as const;

for (const viewport of VIEWPORTS) {
  test(`token reference is stable at ${viewport.name} width`, async ({ page }) => {
    await page.setViewportSize({ width: viewport.width, height: viewport.height });
    await page.goto("/");
    await expect(page.getByRole("heading", { level: 1, name: "Token reference" })).toBeVisible();
    await expect(page).toHaveScreenshot(`tokens-${viewport.name}.png`, { fullPage: true });
  });
}

test("token reference is stable under reduced motion", async ({ page }) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.setViewportSize({ width: 1512, height: 982 });
  await page.goto("/");
  await expect(page.getByRole("heading", { level: 1, name: "Token reference" })).toBeVisible();
  await expect(page).toHaveScreenshot("tokens-reduced-motion.png", { fullPage: true });
});

test("token reference has no critical or serious accessibility violations", async ({ page }) => {
  await page.goto("/");
  await page.getByRole("heading", { level: 1, name: "Token reference" }).waitFor();

  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa"])
    .analyze();

  const blocking = results.violations.filter(
    (violation) => violation.impact === "critical" || violation.impact === "serious"
  );

  expect(blocking, JSON.stringify(blocking.map((v) => v.id), null, 2)).toEqual([]);
});
