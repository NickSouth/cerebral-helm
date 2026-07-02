import { readFileSync, readdirSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { MODE_IDS, MODE_TOKEN_NAMES, isRegisteredModeTokenName, modeTokenCssVar } from "./tokens";
import manifest from "./tokens.manifest.json";

const here = path.dirname(fileURLToPath(import.meta.url));
const tokensCss = readFileSync(path.join(here, "tokens.css"), "utf8");
const appCss = readFileSync(path.join(here, "..", "app.css"), "utf8");
const modesDir = path.join(here, "..", "..", "..", "..", "config", "modes");

function defines(css: string, cssVar: string): boolean {
  return new RegExp(`${cssVar}\\s*:`).test(css);
}

describe("design tokens", () => {
  it("keeps the Node-readable manifest in lockstep with the typed registry", () => {
    expect(manifest.modeThemeTokens).toEqual([...MODE_TOKEN_NAMES]);
  });

  it("defines a CSS custom property for every registered mode token name", () => {
    for (const name of MODE_TOKEN_NAMES) {
      expect(defines(tokensCss, modeTokenCssVar(name))).toBe(true);
    }
  });

  it("resolves every theme token referenced by config/modes/*.json", () => {
    const modeFiles = readdirSync(modesDir).filter((file) => file.endsWith(".json"));
    expect(modeFiles.length).toBeGreaterThan(0);

    for (const file of modeFiles) {
      const config = JSON.parse(readFileSync(path.join(modesDir, file), "utf8"));
      for (const tokenName of [config.theme.accentPrimary, config.theme.accentSecondary]) {
        expect(isRegisteredModeTokenName(tokenName)).toBe(true);
        expect(defines(tokensCss, modeTokenCssVar(tokenName))).toBe(true);
      }
    }
  });

  it("resolves the accent semantic tokens under each data-mode selector", () => {
    for (const mode of MODE_IDS) {
      const block = new RegExp(
        `\\[data-mode="${mode}"\\]\\s*{[^}]*--ch-accent-primary[^}]*--ch-accent-secondary[^}]*}`,
        "s"
      );
      expect(block.test(tokensCss)).toBe(true);
    }
  });

  it("defines keyboard-focus tokens", () => {
    for (const token of [
      "--ch-focus-ring-color",
      "--ch-focus-ring-width",
      "--ch-focus-ring-offset"
    ]) {
      expect(defines(tokensCss, token)).toBe(true);
    }
  });

  it("neutralizes motion tokens under prefers-reduced-motion", () => {
    expect(tokensCss).toMatch(/prefers-reduced-motion:\s*reduce/);
    const reducedBlock = tokensCss.slice(tokensCss.indexOf("prefers-reduced-motion"));
    expect(reducedBlock).toMatch(/--ch-motion-base:\s*0ms/);
  });

  it("keeps raw hex colors out of the component stylesheet (tokens only)", () => {
    expect(appCss).not.toMatch(/#[0-9a-fA-F]{3,8}\b/);
  });
});
