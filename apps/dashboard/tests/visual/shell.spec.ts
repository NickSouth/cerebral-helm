import { test, expect } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

/**
 * The three-zone dashboard shell (NIC-53) is the canonical visual fixture. The bootstrap
 * fixture is fully static (fixed clocks) so screenshots are deterministic — with two exceptions
 * we neutralise here:
 *  1. the ambient outline "flashlight" beam (useAmbientBeam) moves on a random path — we disable
 *     its pseudo-elements before snapshotting;
 *  2. the animated WebGL "Threads" consciousness field (HeimlichConsciousness) renders a fresh,
 *     time-driven frame every run, so it can never match a frozen baseline. We run every snapshot
 *     under `prefers-reduced-motion: reduce`, which makes HeimlichConsciousness render its static
 *     gradient fallback instead of the animated canvas — deterministic, and without masking the
 *     greeting/quick-actions that sit above the full-bleed ribbon.
 */

/** Hide the JS-driven ambient beam so its random position never flakes the baseline. */
const DISABLE_BEAM =
  ".shell-panel::after,.heimlich::after,.bottom-bar::after,.command-surface--launcher::after{display:none !important}";

/** The bottom-bar clock and calendar carry live wall-time; mask them out of every baseline. */
const liveClocks = (page: import("@playwright/test").Page) => [
  page.locator(".bottom-bar__clock"),
  page.locator(".calendar__time"),
  page.locator(".calendar__date")
];

const VIEWPORTS = [
  { name: "compact", width: 1280, height: 900 },
  { name: "laptop", width: 1512, height: 982 },
  { name: "external", width: 1920, height: 1200 }
] as const;

for (const viewport of VIEWPORTS) {
  test(`dashboard shell is stable at ${viewport.name} width`, async ({ page }) => {
    // Freeze the WebGL Heimlich field to its static fallback (see file header).
    await page.emulateMedia({ reducedMotion: "reduce" });
    await page.setViewportSize({ width: viewport.width, height: viewport.height });
    await page.goto("/");
    await expect(page.getByRole("region", { name: "Heimlich" })).toBeVisible();
    await page.addStyleTag({ content: DISABLE_BEAM });
    await expect(page).toHaveScreenshot(`shell-${viewport.name}.png`, {
      fullPage: true,
      mask: liveClocks(page)
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
    mask: liveClocks(page)
  });
});

test("dashboard shell has no critical or serious accessibility violations", async ({ page }) => {
  await page.goto("/");
  await page.getByRole("region", { name: "Heimlich" }).waitFor();

  const results = await new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa"]).analyze();

  const blocking = results.violations.filter(
    (violation) => violation.impact === "critical" || violation.impact === "serious"
  );

  expect(
    blocking,
    JSON.stringify(
      blocking.map((v) => v.id),
      null,
      2
    )
  ).toEqual([]);
});
