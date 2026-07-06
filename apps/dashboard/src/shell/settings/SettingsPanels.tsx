import { useId, useState, type ReactNode } from "react";
import { useDashboardState } from "../../state/DashboardStateProvider";
import { useAppearance } from "../../state/AppearanceProvider";
import { toModeId } from "../../tokens/tokens";
import { Unavailable } from "../../components/Unavailable";
import { humanizeId } from "../labels";
import { useUpdateSettings } from "./useUpdateSettings";
import { PERMISSION_TOOLS } from "./permissionsCatalog";
import wiredManifest from "../quickActions.manifest.json";
import type { SettingsCategoryId } from "./categories";

/** A titled group within a panel. */
function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="settings-section">
      <h3 className="settings-section__title">{title}</h3>
      {children}
    </section>
  );
}

/** A label + value/control row. `hint` explains scope (e.g. "applied on next launch"). */
function Field({ label, hint, children }: { label: string; hint?: string; children: ReactNode }) {
  return (
    <div className="settings-field">
      <div className="settings-field__text">
        <span className="settings-field__label">{label}</span>
        {hint ? <span className="settings-field__hint">{hint}</span> : null}
      </div>
      <div className="settings-field__control">{children}</div>
    </div>
  );
}

/** A read-only value (contract inspection — not an editable control). */
function ReadonlyValue({ children }: { children: ReactNode }) {
  return <span className="settings-readonly">{children}</span>;
}

// --- General --------------------------------------------------------------

function GeneralPanel() {
  const { modes, mode, capabilities } = useDashboardState();
  const updateSettings = useUpdateSettings();
  const selectId = useId();
  const [defaultModeId, setDefaultModeId] = useState(() => toModeId(mode));
  const [windowsStoredByMode, setWindowsStoredByMode] = useState(false);
  const windowsCapability = capabilities?.["native.workspace.windows"];

  function onChange(nextId: string) {
    setDefaultModeId(nextId as typeof defaultModeId);
    void updateSettings({ defaultModeId: nextId });
  }

  function onWindowsToggle(next: boolean) {
    setWindowsStoredByMode(next);
    void updateSettings({ workspace: { windowsStoredByMode: next } });
  }

  return (
    <>
      <Section title="Startup">
        <Field label="Default mode" hint="The mode CerebralHelm opens in — applied on next launch.">
          <select
            id={selectId}
            className="settings-select"
            value={defaultModeId}
            aria-label="Default mode"
            onChange={(event) => onChange(event.target.value)}
          >
            {modes.map((modeView) => (
              <option key={modeView.id} value={modeView.id}>
                {modeView.label}
              </option>
            ))}
          </select>
        </Field>
      </Section>
      <Section title="Workspace">
        <Field
          label="Windows Stored by Mode"
          hint={
            windowsCapability?.available
              ? "Switching modes hides the outgoing mode's windows and returns the stored ones. Quit apps are never relaunched."
              : (windowsCapability?.degradedReason ??
                "Applies on the macOS host: switching modes hides the outgoing mode's windows and returns the stored ones.")
          }
        >
          <label className="settings-switch">
            <input
              type="checkbox"
              checked={windowsStoredByMode}
              aria-label="Windows Stored by Mode"
              onChange={(event) => onWindowsToggle(event.target.checked)}
            />
            <span className="settings-switch__track" aria-hidden="true" />
          </label>
        </Field>
      </Section>
      <Section title="About">
        <Field label="Build">
          <ReadonlyValue>CerebralHelm · pre-Mac (mock bridge)</ReadonlyValue>
        </Field>
        <Field label="Settings schema">
          <ReadonlyValue>1.0.0</ReadonlyValue>
        </Field>
      </Section>
    </>
  );
}

// --- Permissions ----------------------------------------------------------

function PermissionsPanel() {
  return (
    <Section title="Enabled tools">
      <p className="settings-note">
        Risk classification and confirmation policy are set by deterministic policy outside this
        window and cannot be changed here — they are inspected, never overridden.
      </p>
      <ul className="settings-list">
        {PERMISSION_TOOLS.map((tool) => (
          <li key={tool.id} className="settings-list__item">
            <div className="settings-list__text">
              <span className="settings-list__title">{tool.id}</span>
              <span className="settings-list__sub">{tool.purpose}</span>
            </div>
            <div className="settings-list__meta">
              <span className="settings-badge" data-risk={tool.risk}>
                {humanizeId(tool.risk)}
              </span>
              <span className="settings-list__policy">
                {tool.requiresConfirmation ? "Confirms" : "No confirmation"}
              </span>
            </div>
          </li>
        ))}
      </ul>
    </Section>
  );
}

// --- Modes ----------------------------------------------------------------

function ModesPanel() {
  const { modes } = useDashboardState();
  return (
    <Section title="Configured modes">
      <p className="settings-note">
        Switch modes from the dashboard. Configuration is defined in files; this is a read-only
        view.
      </p>
      <ul className="settings-list">
        {modes.map((modeView) => (
          <li key={modeView.id} className="settings-list__item">
            <span
              className="settings-swatch"
              aria-hidden="true"
              style={{
                background: `linear-gradient(135deg, ${modeView.theme.accentPrimary}, ${modeView.theme.accentSecondary})`
              }}
            />
            <div className="settings-list__text">
              <span className="settings-list__title">{modeView.label}</span>
              <span className="settings-list__sub">
                {modeView.quickApps.length} quick apps · {modeView.greeting?.persona ?? "—"}
              </span>
            </div>
          </li>
        ))}
      </ul>
    </Section>
  );
}

// --- Actions --------------------------------------------------------------

const WIRED_ACTION_IDS = new Set(
  Object.keys((wiredManifest as { wiredActions?: Record<string, unknown> }).wiredActions ?? {})
);

function ActionsPanel() {
  const { modes, mode } = useDashboardState();
  const active = modes.find((modeView) => modeView.label === mode) ?? modes[0];
  const actions = active?.quickActions ?? [];

  return (
    <Section title={`Quick actions — ${active?.label ?? ""}`}>
      <p className="settings-note">
        The eight quick-action slots for the active mode, and whether each is wired to a workflow
        yet.
      </p>
      <ul className="settings-list">
        {actions.map((action, index) => (
          <li key={`${action ?? "empty"}-${index}`} className="settings-list__item">
            <div className="settings-list__text">
              <span className="settings-list__title">
                {action ? humanizeId(action) : "Empty slot"}
              </span>
            </div>
            <span className="settings-list__policy">
              {action && WIRED_ACTION_IDS.has(action)
                ? "Wired"
                : action
                  ? "Not wired yet"
                  : "Unconfigured"}
            </span>
          </li>
        ))}
      </ul>
    </Section>
  );
}

// --- Hotkeys --------------------------------------------------------------

/** The curated palette shortcuts, mirroring the native `PaletteShortcutPreset` ids. */
const PALETTE_SHORTCUT_PRESETS: ReadonlyArray<{ id: string; label: string }> = [
  { id: "option-space", label: "⌥Space" },
  { id: "command-shift-space", label: "⌘⇧Space" },
  { id: "control-space", label: "⌃Space" },
  { id: "option-command-k", label: "⌥⌘K" }
];

interface HotkeyWindow extends Window {
  webkit?: { messageHandlers?: { shellControl?: { postMessage(message: unknown): void } } };
  __cerebralHotkey?: { preset?: string; label?: string };
}

/** Ask the native shell to rebind the palette hotkey (a Mac-only concern, off the bridge). */
function setPaletteShortcut(preset: string): void {
  (window as HotkeyWindow).webkit?.messageHandlers?.shellControl?.postMessage({
    action: "setPaletteShortcut",
    preset
  });
}

function HotkeysPanel() {
  const selectId = useId();
  const [preset, setPreset] = useState(
    () => (window as HotkeyWindow).__cerebralHotkey?.preset ?? "option-space"
  );

  function onChange(next: string) {
    setPreset(next);
    setPaletteShortcut(next);
  }

  return (
    <Section title="Command palette">
      <Field
        label="Summon shortcut"
        hint="Press this from anywhere to open the command palette."
      >
        <select
          id={selectId}
          className="settings-select"
          value={preset}
          aria-label="Command palette shortcut"
          onChange={(event) => onChange(event.target.value)}
        >
          {PALETTE_SHORTCUT_PRESETS.map((option) => (
            <option key={option.id} value={option.id}>
              {option.label}
            </option>
          ))}
        </select>
      </Field>
      <p className="settings-note">
        If the shortcut doesn’t respond, another app may already use it — pick a different one.
      </p>
    </Section>
  );
}

// --- Customization --------------------------------------------------------

function CustomizationPanel() {
  const { reducedMotion, setReducedMotion } = useAppearance();
  const updateSettings = useUpdateSettings();

  function onToggle(next: boolean) {
    setReducedMotion(next);
    void updateSettings({ appearance: { reducedMotion: next } });
  }

  return (
    <Section title="Motion">
      <Field
        label="Reduce motion"
        hint="Stills ambient and transition animations across the dashboard."
      >
        <label className="settings-switch">
          <input
            type="checkbox"
            checked={reducedMotion}
            aria-label="Reduce motion"
            onChange={(event) => onToggle(event.target.checked)}
          />
          <span className="settings-switch__track" aria-hidden="true" />
        </label>
      </Field>
    </Section>
  );
}

// --- Setup ----------------------------------------------------------------

function SetupPanel() {
  return (
    <Section title="Setup">
      <p className="settings-note">These arrive with the macOS host.</p>
      <Field label="Integrations & providers">
        <Unavailable label="Requires the macOS host" />
      </Field>
      <Field label="Onboarding">
        <Unavailable label="Requires the macOS host" />
      </Field>
      <Field label="Data location">
        <Unavailable label="Requires the macOS host" />
      </Field>
    </Section>
  );
}

// --- Knowledge ------------------------------------------------------------

function KnowledgePanel() {
  const updateSettings = useUpdateSettings();
  const [rootReference, setRootReference] = useState("");

  function commit() {
    const trimmed = rootReference.trim();
    if (trimmed) {
      void updateSettings({ knowledge: { rootReference: trimmed } });
    }
  }

  return (
    <>
      <Section title="Knowledge root">
        <Field
          label="Root reference"
          hint="Where durable Markdown knowledge lives. Editable now; browsing arrives with the knowledge system."
        >
          <input
            type="text"
            className="settings-input"
            value={rootReference}
            placeholder="e.g. knowledge-root"
            aria-label="Knowledge root reference"
            onChange={(event) => setRootReference(event.target.value)}
            onBlur={commit}
            onKeyDown={(event) => {
              if (event.key === "Enter") {
                commit();
              }
            }}
          />
        </Field>
      </Section>
      <Section title="Library">
        <Field label="Browse notes">
          <Unavailable label="Requires the knowledge system" />
        </Field>
        <Field label="Rebuild index">
          <Unavailable label="Requires the knowledge system" />
        </Field>
      </Section>
    </>
  );
}

/** The category → panel registry — the content router (no per-category conditional in the window). */
export const SETTINGS_PANELS: Readonly<Record<SettingsCategoryId, () => ReactNode>> = {
  general: GeneralPanel,
  permissions: PermissionsPanel,
  modes: ModesPanel,
  actions: ActionsPanel,
  hotkeys: HotkeysPanel,
  customization: CustomizationPanel,
  setup: SetupPanel,
  knowledge: KnowledgePanel
};
