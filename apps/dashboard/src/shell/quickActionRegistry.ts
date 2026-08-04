import { humanizeId } from "./labels";
import registryDocument from "./quickActions.registry.json";

/**
 * The dispatch registry: the single catalog of every planned quick action (docs/quick-actions/PLAN.md,
 * phase 0). One entry per action id carries its display label, its icon, the archetype it is built
 * from, and — only once the action actually exists — the runtime `target` the dashboard dispatches it to.
 *
 * It replaces the three-way split this used to be: a build-time wiring manifest, a handler map keyed by
 * a separate name, and a regex that inferred layout actions from their id. A layout action now *declares*
 * its mode instead of having it parsed back out of the id.
 *
 * An entry with **no target is planned, not built** — the slot renders labelled but disabled, which is
 * honest rather than hiding it. The `validateQuickActionRegistry` gate (scripts/validate-config.mjs)
 * guarantees the reverse direction too: every declared target resolves, and every id a mode configures
 * exists here, so a typo in `config/modes/*.json` is a build failure rather than a mystery button.
 */
export type QuickActionArchetype = "report" | "input" | "picker" | "fire-and-forget";

/** Where a built action dispatches to. Mirrored by the config gate, which resolves each kind. */
export type QuickActionTarget =
  | { readonly kind: "handler"; readonly handler: string }
  | { readonly kind: "workflow"; readonly workflow: string }
  | { readonly kind: "layout"; readonly mode: string }
  /** Opens a composed `ReportDocument` in the centre panel's Report region. */
  | { readonly kind: "report" }
  /** Opens this action's form in the centre panel's Input region. */
  | { readonly kind: "input" };

export interface QuickActionEntry {
  readonly label: string;
  /**
   * Icon name for the slot's leading glyph. Carried here (beside `label` and `archetype`) because the
   * registry is the one place that knows what an action *is*; slot icons render in a later increment.
   */
  readonly icon: string;
  readonly archetype: QuickActionArchetype;
  /**
   * Optional visual weight. `danger` renders an outline-red slot — reserved for `shut-down`, the
   * only differently-coloured action. Outline rather than filled: a solid red button reads as
   * *danger, do not touch*, but this one is pressed on purpose, so the weight belongs on the
   * confirmation rather than the tile (docs/quick-actions/PLAN.md).
   */
  readonly tone?: "danger";
  /** Absent while the action is planned but not built. */
  readonly target?: QuickActionTarget;
}

const ACTIONS = registryDocument.actions as unknown as Readonly<Record<string, QuickActionEntry>>;

/** The registered entry for an action id, or `null` for an id no mode should be configuring. */
export function quickActionEntry(id: string): QuickActionEntry | null {
  return ACTIONS[id] ?? null;
}

/**
 * An action's display label. Falls back to humanizing the id: the gate makes an unregistered id
 * unreachable in a valid build, so this only covers a runtime-supplied id (a stale persisted config),
 * where a readable label beats a blank slot.
 */
export function quickActionLabel(id: string): string {
  return ACTIONS[id]?.label ?? humanizeId(id);
}

/** Whether an action is built (has a dispatch target) rather than planned. */
export function isQuickActionWired(id: string): boolean {
  return ACTIONS[id]?.target != null;
}

/** The slot's visual tone, or `null` for the default treatment. */
export function quickActionTone(id: string): "danger" | null {
  return ACTIONS[id]?.tone ?? null;
}
