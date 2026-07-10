import { useEffect, useState, type ReactNode } from "react";
import { useDashboardState } from "../../state/DashboardStateProvider";
import { useAppearance, DEFAULT_ASSISTANT_NAME } from "../../state/AppearanceProvider";
import { toModeId, MODE_IDS, MODE_DEFAULT_COLORS, type ModeTokenName } from "../../tokens/tokens";
import { Unavailable } from "../../components/Unavailable";
import { humanizeId } from "../labels";
import { useUpdateSettings } from "./useUpdateSettings";
import { useSettingsSnapshot } from "./SettingsSnapshotProvider";
import { postShellControl, isShellControlAvailable } from "../shellControl";
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

/**
 * Shown while a panel's persisted values are being read (NIC-141). A panel whose
 * controls seed from the settings snapshot never renders them until the read settles,
 * so a wrong default is never briefly editable.
 */
function SettingsLoading() {
  return (
    <p className="settings-note" role="status">
      Loading your settings…
    </p>
  );
}

// --- Shared control seeds --------------------------------------------------

/**
 * The persisted sentinel for "no explicit main display" — never a real display
 * id, so the shell's lookup misses and falls back to the system primary. The
 * settings-patch contract has no clear/reset semantics, so an explicit value is
 * how the user returns to the default.
 */
const SYSTEM_PRIMARY = "system-primary";

interface LoginItemWindow extends Window {
  __cerebralLoginItem?: { status?: string };
  __cerebralLoginItemUpdate?: (status: string) => void;
}

interface KnowledgeRootWindow extends Window {
  /** Set by the native shell after the NSOpenPanel folder picker resolves (NIC-138). */
  __cerebralKnowledgeRootUpdate?: (path: string) => void;
}

/**
 * "Launch at login" (NIC-89): the value is the LIVE OS login-item status seeded
 * and pushed by the native shell over the private shellControl channel — never
 * the settings store, which could silently diverge from System Settings. In a
 * plain browser there is no shell, so the toggle is honest-disabled.
 */
function LaunchAtLoginField() {
  const [status, setStatus] = useState<string | null>(
    () => (window as LoginItemWindow).__cerebralLoginItem?.status ?? null
  );

  useEffect(() => {
    (window as LoginItemWindow).__cerebralLoginItemUpdate = (next) => setStatus(next);
    return () => {
      delete (window as LoginItemWindow).__cerebralLoginItemUpdate;
    };
  }, []);

  const available = status !== null;
  const checked = status === "enabled" || status === "requires-approval";
  const hint = !available
    ? "Available on the macOS host."
    : status === "requires-approval"
      ? "Waiting for approval — allow CerebralHelm under System Settings → General → Login Items."
      : "Opens CerebralHelm automatically when you log in.";

  return (
    <Field label="Launch at login" hint={hint}>
      <label className="settings-switch">
        <input
          type="checkbox"
          checked={checked}
          disabled={!available}
          aria-label="Launch at login"
          onChange={(event) => postShellControl("setLoginItem", { enabled: event.target.checked })}
        />
        <span className="settings-switch__track" aria-hidden="true" />
      </label>
    </Field>
  );
}

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

// --- General --------------------------------------------------------------

function GeneralPanel() {
  // Gate on the persisted read so the Main display control seeds from settled state (NIC-141).
  const { status } = useSettingsSnapshot();
  return status === "loading" ? <SettingsLoading /> : <GeneralPanelBody />;
}

function GeneralPanelBody() {
  const { displayTopology } = useDashboardState();
  // Ready → persisted values; error → null → fall back to the safe defaults.
  const { snapshot } = useSettingsSnapshot();
  const { reducedMotion, setReducedMotion } = useAppearance();
  const updateSettings = useUpdateSettings();
  const [mainDisplayId, setMainDisplayId] = useState(
    () => snapshot?.workspace.mainDisplayId ?? SYSTEM_PRIMARY
  );
  const [preset, setPreset] = useState(
    () => (window as HotkeyWindow).__cerebralHotkey?.preset ?? "option-space"
  );
  // Only stable identities may be persisted (NIC-87 safe-degradation rule): a
  // session-scoped fallback id would silently stop matching after reconnect.
  const selectableDisplays = (displayTopology?.displays ?? []).filter(
    (display) => display.stableIdentity
  );

  function onMainDisplayChange(nextId: string) {
    setMainDisplayId(nextId);
    // Durable via the validated settings path; the shellControl post applies it
    // live (the shell re-hosts backdrops without waiting for a restart).
    void updateSettings({ workspace: { mainDisplayId: nextId } });
    postShellControl("setMainDisplay", { id: nextId });
  }

  function onReducedMotionToggle(next: boolean) {
    setReducedMotion(next);
    void updateSettings({ appearance: { reducedMotion: next } });
  }

  function onShortcutChange(next: string) {
    setPreset(next);
    setPaletteShortcut(next);
  }

  return (
    <>
      <Section title="Startup">
        <LaunchAtLoginField />
      </Section>
      <Section title="Display">
        <Field
          label="Main display"
          hint="Where the dashboard's conversation and the command palette appear. Displays without a stable identity fall back to the system primary."
        >
          <select
            className="settings-select"
            value={mainDisplayId}
            aria-label="Main display"
            onChange={(event) => onMainDisplayChange(event.target.value)}
          >
            <option value={SYSTEM_PRIMARY}>System primary</option>
            {selectableDisplays.map((display) => (
              <option key={display.id} value={display.id}>
                {display.name}
                {display.primary ? " (primary)" : ""}
              </option>
            ))}
          </select>
        </Field>
      </Section>
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
              onChange={(event) => onReducedMotionToggle(event.target.checked)}
            />
            <span className="settings-switch__track" aria-hidden="true" />
          </label>
        </Field>
      </Section>
      <Section title="Command palette">
        <Field label="Summon shortcut" hint="Press this from anywhere to open the command palette.">
          <select
            className="settings-select"
            value={preset}
            aria-label="Command palette shortcut"
            onChange={(event) => onShortcutChange(event.target.value)}
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
  // The tightening toggle seeds from the persisted read (NIC-141).
  const { status } = useSettingsSnapshot();
  return status === "loading" ? <SettingsLoading /> : <PermissionsPanelBody />;
}

function PermissionsPanelBody() {
  const { snapshot } = useSettingsSnapshot();
  const updateSettings = useUpdateSettings();
  const [confirmAll, setConfirmAll] = useState(() => snapshot?.confirmAllActions ?? false);

  function onToggle(next: boolean) {
    setConfirmAll(next);
    void updateSettings({ confirmAllActions: next });
  }

  return (
    <>
      <Section title="Confirmation">
        <Field
          label="Ask before all actions"
          hint="Require confirmation before every action across the app. This only tightens — it adds confirmation and can never remove one that policy already requires. Applies on next launch."
        >
          <label className="settings-switch">
            <input
              type="checkbox"
              checked={confirmAll}
              aria-label="Ask before all actions"
              onChange={(event) => onToggle(event.target.checked)}
            />
            <span className="settings-switch__track" aria-hidden="true" />
          </label>
        </Field>
      </Section>
      <Section title="Enabled tools">
        <p className="settings-note">
          Each tool&apos;s risk class and baseline confirmation are deterministic and cannot be
          relaxed here — the switch above only ever adds confirmation, never removes it.
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
    </>
  );
}

// --- Modes ----------------------------------------------------------------

function ModesPanel() {
  // The default-mode and window-behavior controls seed from the persisted read (NIC-141).
  const { status } = useSettingsSnapshot();
  return status === "loading" ? <SettingsLoading /> : <ModesPanelBody />;
}

function ModesPanelBody() {
  const { modes, mode, capabilities } = useDashboardState();
  const { snapshot } = useSettingsSnapshot();
  const updateSettings = useUpdateSettings();
  const [defaultModeId, setDefaultModeId] = useState(
    () => snapshot?.defaultModeId ?? toModeId(mode)
  );
  const [windowsStoredByMode, setWindowsStoredByMode] = useState(
    () => snapshot?.workspace.windowsStoredByMode ?? false
  );
  const windowsCapability = capabilities?.["native.workspace.windows"];

  function onDefaultModeChange(nextId: string) {
    setDefaultModeId(nextId as typeof defaultModeId);
    void updateSettings({ defaultModeId: nextId });
  }

  function onWindowsToggle(next: boolean) {
    setWindowsStoredByMode(next);
    void updateSettings({ workspace: { windowsStoredByMode: next } });
  }

  return (
    <>
      <Section title="Default mode">
        <Field label="Default mode" hint="The mode CerebralHelm opens in — applied on next launch.">
          <select
            className="settings-select"
            value={defaultModeId}
            aria-label="Default mode"
            onChange={(event) => onDefaultModeChange(event.target.value)}
          >
            {modes.map((modeView) => (
              <option key={modeView.id} value={modeView.id}>
                {modeView.label}
              </option>
            ))}
          </select>
        </Field>
      </Section>
      <Section title="Window behavior">
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
      <Section title="Configured modes">
        <p className="settings-note">
          Switch modes from the dashboard. Colors and the assistant name are customizable under
          Customization; this is a read-only summary.
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
    </>
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
        yet. Building and rebinding actions arrives in a later pass.
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

// --- Customization --------------------------------------------------------

const MODE_COLOR_CHANNELS = ["primary", "secondary"] as const;

function CustomizationPanel() {
  // Seeds from — and live-updates — the global assistant name and per-mode accent colors
  // (AppearanceProvider, fed by getSettings). Editing recolors/renames the dashboard in
  // place where they share a tree (the browser overlay); the edit persists on commit.
  const { assistantName, setAssistantName, modeColors, setModeColor } = useAppearance();
  const updateSettings = useUpdateSettings();

  function commitName() {
    const trimmed = assistantName.trim();
    // Never persist an empty name — restore the default identity instead.
    const next = trimmed.length === 0 ? DEFAULT_ASSISTANT_NAME : trimmed;
    if (next !== assistantName) {
      setAssistantName(next);
    }
    void updateSettings({ appearance: { assistantName: next } });
  }

  // The override map is replaced wholesale on write, so persist the full current set of
  // overrides (defaults are never stored — an un-edited channel stays absent).
  function commitColors() {
    void updateSettings({ modeColors });
  }

  return (
    <>
      <Section title="Assistant">
        <Field
          label="Assistant name"
          hint="The name shown for your assistant across the dashboard. Defaults to Heimlich."
        >
          <input
            type="text"
            className="settings-input"
            value={assistantName}
            maxLength={40}
            placeholder={DEFAULT_ASSISTANT_NAME}
            aria-label="Assistant name"
            onChange={(event) => setAssistantName(event.target.value)}
            onBlur={commitName}
            onKeyDown={(event) => {
              if (event.key === "Enter") {
                commitName();
              }
            }}
          />
        </Field>
      </Section>
      <Section title="Mode colors">
        <p className="settings-note">
          Each mode&apos;s primary and secondary accent. Changes recolor the dashboard live; leave a
          swatch untouched to keep its shipped color.
        </p>
        {MODE_IDS.map((modeId) => (
          <Field key={modeId} label={humanizeId(modeId)}>
            <div className="settings-color-pair">
              {MODE_COLOR_CHANNELS.map((channel) => {
                const tokenName = `${modeId}.${channel}` as ModeTokenName;
                const value = modeColors[tokenName] ?? MODE_DEFAULT_COLORS[tokenName];
                return (
                  <input
                    key={channel}
                    type="color"
                    className="settings-color"
                    value={value}
                    aria-label={`${humanizeId(modeId)} ${channel} color`}
                    onChange={(event) => setModeColor(tokenName, event.target.value)}
                    onBlur={commitColors}
                  />
                );
              })}
            </div>
          </Field>
        ))}
      </Section>
    </>
  );
}

// --- Setup ----------------------------------------------------------------

function SetupPanel() {
  // The knowledge-root control seeds from the persisted read (NIC-141).
  const { status } = useSettingsSnapshot();
  return status === "loading" ? <SettingsLoading /> : <SetupPanelBody />;
}

function SetupPanelBody() {
  const { snapshot } = useSettingsSnapshot();
  const updateSettings = useUpdateSettings();
  const [rootReference, setRootReference] = useState(() => snapshot?.knowledge.rootReference ?? "");
  // The native NSOpenPanel picker is a macOS-host concern (off the versioned bridge);
  // in a plain browser there is no channel, so the Browse button is honest-disabled.
  const canBrowse = isShellControlAvailable();

  function persist(next: string) {
    const trimmed = next.trim();
    if (trimmed) {
      void updateSettings({ knowledge: { rootReference: trimmed } });
    }
  }

  // The native shell posts back the folder chosen in the Finder picker (NIC-138): reflect
  // it and persist through the validated settings path. Registered once for the panel's life.
  useEffect(() => {
    const target = window as KnowledgeRootWindow;
    target.__cerebralKnowledgeRootUpdate = (path: string) => {
      setRootReference(path);
      persist(path);
    };
    return () => {
      delete target.__cerebralKnowledgeRootUpdate;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <>
      <Section title="Knowledge root">
        <Field
          label="Root folder"
          hint="Where durable Markdown knowledge lives. Choose a folder, or type a path. Changing it re-points to the new location — it never moves or deletes what is already there. Applies with the knowledge system."
        >
          <div className="settings-root-picker">
            <input
              type="text"
              className="settings-input"
              value={rootReference}
              placeholder="e.g. ~/CerebralHelm/knowledge"
              aria-label="Knowledge root reference"
              onChange={(event) => setRootReference(event.target.value)}
              onBlur={() => persist(rootReference)}
              onKeyDown={(event) => {
                if (event.key === "Enter") {
                  persist(rootReference);
                }
              }}
            />
            <button
              type="button"
              className="settings-button"
              disabled={!canBrowse}
              title={canBrowse ? undefined : "Choosing a folder requires the macOS host"}
              onClick={() => postShellControl("pickKnowledgeRoot")}
            >
              Browse…
            </button>
          </div>
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
      <Section title="Integrations & onboarding">
        <Field label="Integrations & providers">
          <Unavailable label="Requires the macOS host" />
        </Field>
        <Field label="Onboarding">
          <Unavailable label="Requires the macOS host" />
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
  customization: CustomizationPanel,
  setup: SetupPanel
};
