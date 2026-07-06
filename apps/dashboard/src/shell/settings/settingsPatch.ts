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
  readonly appearance?: {
    readonly density?: "comfortable" | "compact";
    readonly reducedMotion?: boolean;
  };
  readonly hotkeys?: { readonly commandPalette?: string };
  readonly knowledge?: { readonly rootReference?: string };
  readonly workspace?: { readonly windowsStoredByMode?: boolean };
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
  "appearance",
  "hotkeys",
  "knowledge",
  "workspace",
  "extensions"
]);
const ALLOWED_APPEARANCE_KEYS = new Set(["density", "reducedMotion"]);

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

  return { valid: errors.length === 0, errors };
}

let patchCounter = 0;

/** Build a schema-shaped settings patch from a `changes` delta. Ids are stable per session for tests. */
export function buildSettingsPatch(changes: SettingsPatchChanges): SettingsPatch {
  patchCounter += 1;
  const patchId = `set_ui${String(patchCounter).padStart(8, "0")}`;
  return { schemaVersion: SCHEMA_VERSION, patchId, changes };
}
