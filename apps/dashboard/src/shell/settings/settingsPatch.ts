/**
 * The settings-patch shape + validator (NIC-63). Mirrors
 * `packages/contracts/schemas/config/settings-patch.schema.json` — the authoritative config
 * validation path (FR-CFG-04). The UI never invents its own rules: it builds a patch and submits
 * it through `updateSettings`, and the (mock) bridge validates with exactly this allowlist. That is
 * why a risk-override-shaped patch (`toolRiskOverrides`) is rejected here just as the schema rejects
 * it — permission/risk policy is deterministic and cannot be weakened through settings (ADR-003).
 */

export interface SettingsPatchChanges {
  readonly defaultModeId?: string;
  readonly confirmAllActions?: boolean;
  readonly appearance?: {
    readonly density?: "comfortable" | "compact";
    readonly reducedMotion?: boolean;
    readonly assistantName?: string;
  };
  readonly hotkeys?: { readonly commandPalette?: string };
  readonly knowledge?: { readonly rootReference?: string };
  readonly workspace?: {
    readonly windowsStoredByMode?: boolean;
    readonly mainDisplayId?: string;
    readonly layoutDisplayId?: string;
  };
  /** Per-mode accent overrides keyed by design-token name → `#rrggbb`. */
  readonly modeColors?: Readonly<Record<string, string>>;
  /** The user's tracked stock symbols for the Executive Stocks widget (NIC-128). */
  readonly stocks?: { readonly tickers?: readonly string[] };
  readonly extensions?: Readonly<Record<string, unknown>>;
}

export interface SettingsPatch {
  readonly schemaVersion: string;
  readonly patchId: string;
  readonly changes: SettingsPatchChanges;
}

export interface PatchValidation {
  readonly valid: boolean;
  readonly errors: readonly string[];
}

const SCHEMA_VERSION = "1.0.0";
const MODE_ID_PATTERN = /^[a-z][a-z0-9-]*$/;
const DENSITY_VALUES = new Set(["comfortable", "compact"]);
const ALLOWED_CHANGE_KEYS = new Set([
  "defaultModeId",
  "confirmAllActions",
  "appearance",
  "hotkeys",
  "knowledge",
  "workspace",
  "modeColors",
  "stocks",
  "extensions"
]);
const ALLOWED_APPEARANCE_KEYS = new Set(["density", "reducedMotion", "assistantName"]);
const ASSISTANT_NAME_MAX_LENGTH = 40;
const MODE_COLOR_KEY_PATTERN = /^(executive|developer|school|entertainment)\.(primary|secondary)$/;
const HEX_COLOR_PATTERN = /^#[0-9a-fA-F]{6}$/;
const TICKER_SYMBOL_PATTERN = /^[A-Za-z][A-Za-z0-9.-]{0,9}$/;
const TICKERS_MAX_COUNT = 20;

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/**
 * Validate a `changes` object against the settings-patch allowlist. Returns every violation so the
 * caller can surface them; an unknown key (e.g. `toolRiskOverrides`) is a hard rejection.
 */
export function validateSettingsChanges(changes: unknown): PatchValidation {
  const errors: string[] = [];
  if (!isPlainObject(changes)) {
    return { valid: false, errors: ["changes must be an object"] };
  }

  for (const key of Object.keys(changes)) {
    if (!ALLOWED_CHANGE_KEYS.has(key)) {
      errors.push(`Unknown setting "${key}" — not permitted by the settings-patch contract`);
    }
  }

  if ("defaultModeId" in changes) {
    const value = changes.defaultModeId;
    if (typeof value !== "string" || !MODE_ID_PATTERN.test(value)) {
      errors.push("defaultModeId must be a lowercase mode id");
    }
  }

  if ("confirmAllActions" in changes && typeof changes.confirmAllActions !== "boolean") {
    errors.push("confirmAllActions must be a boolean");
  }

  if ("appearance" in changes) {
    const appearance = changes.appearance;
    if (!isPlainObject(appearance)) {
      errors.push("appearance must be an object");
    } else {
      for (const key of Object.keys(appearance)) {
        if (!ALLOWED_APPEARANCE_KEYS.has(key)) {
          errors.push(`Unknown appearance setting "${key}"`);
        }
      }
      if ("density" in appearance && !DENSITY_VALUES.has(String(appearance.density))) {
        errors.push("appearance.density must be comfortable or compact");
      }
      if ("reducedMotion" in appearance && typeof appearance.reducedMotion !== "boolean") {
        errors.push("appearance.reducedMotion must be a boolean");
      }
      if ("assistantName" in appearance) {
        const name = appearance.assistantName;
        if (typeof name !== "string" || name.length < 1 || name.length > ASSISTANT_NAME_MAX_LENGTH) {
          errors.push(`appearance.assistantName must be 1–${ASSISTANT_NAME_MAX_LENGTH} characters`);
        }
      }
    }
  }

  if ("knowledge" in changes) {
    const knowledge = changes.knowledge;
    if (
      !isPlainObject(knowledge) ||
      ("rootReference" in knowledge && typeof knowledge.rootReference !== "string")
    ) {
      errors.push("knowledge.rootReference must be a string");
    }
  }

  if ("workspace" in changes) {
    const workspace = changes.workspace;
    if (
      !isPlainObject(workspace) ||
      ("windowsStoredByMode" in workspace && typeof workspace.windowsStoredByMode !== "boolean")
    ) {
      errors.push("workspace.windowsStoredByMode must be a boolean");
    }
    if (
      isPlainObject(workspace) &&
      "mainDisplayId" in workspace &&
      (typeof workspace.mainDisplayId !== "string" || workspace.mainDisplayId.length === 0)
    ) {
      errors.push("workspace.mainDisplayId must be a non-empty string");
    }
    if (
      isPlainObject(workspace) &&
      "layoutDisplayId" in workspace &&
      (typeof workspace.layoutDisplayId !== "string" || workspace.layoutDisplayId.length === 0)
    ) {
      errors.push("workspace.layoutDisplayId must be a non-empty string");
    }
  }

  if ("hotkeys" in changes) {
    const hotkeys = changes.hotkeys;
    if (
      !isPlainObject(hotkeys) ||
      ("commandPalette" in hotkeys && typeof hotkeys.commandPalette !== "string")
    ) {
      errors.push("hotkeys.commandPalette must be a string");
    }
  }

  if ("modeColors" in changes) {
    const modeColors = changes.modeColors;
    if (!isPlainObject(modeColors)) {
      errors.push("modeColors must be an object");
    } else {
      for (const [key, value] of Object.entries(modeColors)) {
        if (!MODE_COLOR_KEY_PATTERN.test(key)) {
          errors.push(`modeColors key "${key}" is not a known mode accent token`);
        }
        if (typeof value !== "string" || !HEX_COLOR_PATTERN.test(value)) {
          errors.push(`modeColors.${key} must be a #rrggbb hex color`);
        }
      }
    }
  }

  if ("stocks" in changes) {
    const stocks = changes.stocks;
    if (!isPlainObject(stocks)) {
      errors.push("stocks must be an object");
    } else {
      for (const key of Object.keys(stocks)) {
        if (key !== "tickers") {
          errors.push(`Unknown stocks setting "${key}"`);
        }
      }
      if ("tickers" in stocks) {
        const tickers = stocks.tickers;
        if (!Array.isArray(tickers)) {
          errors.push("stocks.tickers must be an array");
        } else {
          if (tickers.length > TICKERS_MAX_COUNT) {
            errors.push(`stocks.tickers may list at most ${TICKERS_MAX_COUNT} symbols`);
          }
          for (const symbol of tickers) {
            if (typeof symbol !== "string" || !TICKER_SYMBOL_PATTERN.test(symbol)) {
              errors.push(`stocks.tickers entry "${String(symbol)}" is not a valid ticker symbol`);
            }
          }
        }
      }
    }
  }

  return { valid: errors.length === 0, errors };
}

let patchCounter = 0;

/** Build a schema-shaped settings patch from a `changes` delta. Ids are stable per session for tests. */
export function buildSettingsPatch(changes: SettingsPatchChanges): SettingsPatch {
  patchCounter += 1;
  const patchId = `set_ui${String(patchCounter).padStart(8, "0")}`;
  return { schemaVersion: SCHEMA_VERSION, patchId, changes };
}
