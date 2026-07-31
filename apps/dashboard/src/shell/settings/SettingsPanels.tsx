import { useEffect, useState, type ReactNode } from "react";
import { useBridge } from "../../state/BridgeProvider";
import { useDashboardState } from "../../state/DashboardStateProvider";
import { LayoutEditor } from "./LayoutEditor";
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
import type { CalendarInfo, CanvasStatus, CanvasStatusItem } from "../../bridge/cerebralBridge";

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

/** Per-section Save/Cancel/Restore footer for the edit-style panels (owner decision,
 *  2026-07-10): edits stage as a draft and only apply on Save; Cancel reverts to the last
 *  saved values; Restore populates the draft with the shipped defaults (then you Save). */
function SectionActions({
  dirty,
  onSave,
  onCancel,
  onRestore
}: {
  dirty: boolean;
  onSave: () => void;
  onCancel: () => void;
  onRestore?: () => void;
}) {
  return (
    <div className="settings-actions">
      {onRestore ? (
        <button type="button" className="settings-button settings-button--ghost" onClick={onRestore}>
          Restore defaults
        </button>
      ) : null}
      <div className="settings-actions__spacer" />
      <button
        type="button"
        className="settings-button settings-button--ghost"
        onClick={onCancel}
        disabled={!dirty}
      >
        Cancel
      </button>
      <button
        type="button"
        className="settings-button settings-button--primary"
        onClick={onSave}
        disabled={!dirty}
      >
        Save
      </button>
    </div>
  );
}

/** Shallow equality for a per-mode color-override map (key order independent). */
function colorMapsEqual(a: Record<string, string>, b: Record<string, string>): boolean {
  const keys = Object.keys(a);
  if (keys.length !== Object.keys(b).length) {
    return false;
  }
  return keys.every((key) => a[key] === b[key]);
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
  const [layoutDisplayId, setLayoutDisplayId] = useState(
    () => snapshot?.workspace.layoutDisplayId ?? SYSTEM_PRIMARY
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

  function onLayoutDisplayChange(nextId: string) {
    setLayoutDisplayId(nextId);
    // Durable via the validated settings path; the shellControl post applies it
    // live (the shell re-targets layout opens + moves the hotswap pill without a
    // restart, NIC-142).
    void updateSettings({ workspace: { layoutDisplayId: nextId } });
    postShellControl("setLayoutDisplay", { id: nextId });
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
        <Field
          label="Layout display"
          hint="Which display layout mode opens on — and the only one whose bottom bar shows the layout hotswap. Displays without a stable identity fall back to the main display."
        >
          <select
            className="settings-select"
            value={layoutDisplayId}
            aria-label="Layout display"
            onChange={(event) => onLayoutDisplayChange(event.target.value)}
          >
            <option value={SYSTEM_PRIMARY}>Same as main display</option>
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
          hint="Require confirmation before every action across the app. This only tightens — it adds confirmation and can never remove one that policy already requires. Takes effect immediately."
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
  // Which mode's layout editor is open inline (the plain-browser fallback). In the
  // native shell the "Edit layout" button opens a dedicated window instead (NIC-142).
  const [editingModeId, setEditingModeId] = useState<string | null>(null);

  function onDefaultModeChange(nextId: string) {
    setDefaultModeId(nextId as typeof defaultModeId);
    void updateSettings({ defaultModeId: nextId });
  }

  function onWindowsToggle(next: boolean) {
    setWindowsStoredByMode(next);
    void updateSettings({ workspace: { windowsStoredByMode: next } });
  }

  function openLayoutEditor(modeId: string) {
    // Prefer the dedicated native editor window; fall back to the inline editor when
    // there is no native channel (a plain browser).
    if (!postShellControl("openLayoutEditor", { modeId })) {
      setEditingModeId((current) => (current === modeId ? null : modeId));
    }
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
      <Section title="Mode layouts">
        <p className="settings-note">
          Author each mode's window arrangement — which apps and URLs open where, and the hotswap
          window. Executive has no layout.
        </p>
        <ul className="settings-list">
          {modes
            .filter((modeView) => modeView.id !== "executive")
            .map((modeView) => (
              <li key={modeView.id} className="settings-list__item">
                <span className="settings-list__title">{modeView.label}</span>
                <button
                  type="button"
                  className="settings-button"
                  aria-label={`Edit ${modeView.label} layout`}
                  onClick={() => openLayoutEditor(modeView.id)}
                >
                  Edit layout
                </button>
              </li>
            ))}
        </ul>
        {editingModeId ? (
          <LayoutEditor
            key={editingModeId}
            modeId={editingModeId}
            label={modes.find((modeView) => modeView.id === editingModeId)?.label ?? humanizeId(editingModeId)}
            onClose={() => setEditingModeId(null)}
          />
        ) : null}
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
  // Draft controls seed from the persisted read (NIC-141); edits stage until Save.
  const { status } = useSettingsSnapshot();
  return status === "loading" ? <SettingsLoading /> : <CustomizationPanelBody />;
}

function CustomizationPanelBody() {
  const { snapshot } = useSettingsSnapshot();
  const updateSettings = useUpdateSettings();

  // "baseline" = last saved values; "draft" = what the controls show. They diverge while
  // editing (dirty) and re-converge on Save/Cancel. Applying the saved values live to every
  // surface is the bridge's job (the settings.changed event) — this panel only stages + persists.
  const [baselineName, setBaselineName] = useState(snapshot?.appearance.assistantName ?? DEFAULT_ASSISTANT_NAME);
  const [baselineColors, setBaselineColors] = useState<Record<string, string>>(snapshot?.modeColors ?? {});
  const [draftName, setDraftName] = useState(baselineName);
  const [draftColors, setDraftColors] = useState<Record<string, string>>(baselineColors);

  const nextName = draftName.trim() || DEFAULT_ASSISTANT_NAME;
  const dirty = nextName !== baselineName || !colorMapsEqual(draftColors, baselineColors);

  function save() {
    void updateSettings({ appearance: { assistantName: nextName }, modeColors: draftColors });
    setDraftName(nextName);
    setBaselineName(nextName);
    setBaselineColors(draftColors);
  }
  function cancel() {
    setDraftName(baselineName);
    setDraftColors(baselineColors);
  }
  function restore() {
    setDraftName(DEFAULT_ASSISTANT_NAME);
    setDraftColors({});
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
            value={draftName}
            maxLength={40}
            placeholder={DEFAULT_ASSISTANT_NAME}
            aria-label="Assistant name"
            onChange={(event) => setDraftName(event.target.value)}
          />
        </Field>
      </Section>
      <Section title="Mode colors">
        <p className="settings-note">
          Each mode&apos;s primary and secondary accent. Changes apply to the dashboard when you
          save; leave a swatch untouched to keep its shipped color.
        </p>
        {MODE_IDS.map((modeId) => (
          <Field key={modeId} label={humanizeId(modeId)}>
            <div className="settings-color-pair">
              {MODE_COLOR_CHANNELS.map((channel) => {
                const tokenName = `${modeId}.${channel}` as ModeTokenName;
                const value = draftColors[tokenName] ?? MODE_DEFAULT_COLORS[tokenName];
                return (
                  <input
                    key={channel}
                    type="color"
                    className="settings-color"
                    value={value}
                    aria-label={`${humanizeId(modeId)} ${channel} color`}
                    onChange={(event) =>
                      setDraftColors((prev) => ({ ...prev, [tokenName]: event.target.value }))
                    }
                  />
                );
              })}
            </div>
          </Field>
        ))}
      </Section>
      <SectionActions dirty={dirty} onSave={save} onCancel={cancel} onRestore={restore} />
    </>
  );
}

// --- Setup ----------------------------------------------------------------

/** The logical Keychain references for the provider API keys (NIC-134 TMDB, NIC-128 Finnhub).
 *  Each matches the descriptor reference pattern `^[a-z][a-z0-9_]*$` so config, keychain, and
 *  this UI agree. */
const TMDB_SECRET_REFERENCE = "tmdb_api_key";
const FINNHUB_SECRET_REFERENCE = "finnhub_api_key";
const NEWSDATA_SECRET_REFERENCE = "newsdata_api_key";
const GITHUB_SECRET_REFERENCE = "github_api_token";
const SPOTIFY_CLIENT_ID_REFERENCE = "spotify_client_id";
const SPOTIFY_OAUTH_REFERENCE = "spotify_oauth";

/**
 * A masked API-key provisioning field for a provider (generalized from the TMDB field, NIC-134;
 * NIC-128 adds Finnhub): stores the key in the Keychain through the `storeSecret` bridge op and
 * shows whether one is set via `getSecretStatus` — presence only, the value is never read back
 * into the field. The value the user types is sent once on Save and then cleared; it never lands
 * in config or a log (FR-CFG-03, FR-OBS-03).
 */
function ProviderKeyField({
  reference,
  label,
  hint,
  placeholder
}: {
  reference: string;
  label: string;
  hint: string;
  placeholder: string;
}) {
  const bridge = useBridge();
  const [bound, setBound] = useState<boolean | null>(null); // null while the status read settles
  const [draft, setDraft] = useState("");
  const [phase, setPhase] = useState<"idle" | "saving" | "error">("idle");

  useEffect(() => {
    let active = true;
    void bridge
      .getSecretStatus({ reference })
      .then((result) => {
        if (active) setBound(result.bound);
      })
      .catch(() => {
        if (active) setBound(false);
      });
    return () => {
      active = false;
    };
  }, [bridge, reference]);

  const canSave = draft.trim().length > 0 && phase !== "saving";

  function save() {
    const value = draft.trim();
    if (!value) return;
    setPhase("saving");
    void bridge
      .storeSecret({ reference, value })
      .then((result) => {
        if (result.stored) {
          setBound(true);
          setDraft(""); // never retain the secret in the field
          setPhase("idle");
        } else {
          setPhase("error");
        }
      })
      .catch(() => setPhase("error"));
  }

  const statusLabel = bound === null ? "Checking…" : bound ? "Key set" : "Not set";

  return (
    <Field label={label} hint={hint}>
      <div className="settings-secret">
        <span className="settings-secret__status" data-bound={bound === true}>
          {statusLabel}
        </span>
        <input
          type="password"
          className="settings-input"
          value={draft}
          placeholder={bound ? "Enter a new key to replace it" : placeholder}
          aria-label={label}
          autoComplete="off"
          onChange={(event) => setDraft(event.target.value)}
        />
        <button
          type="button"
          className="settings-button settings-button--primary"
          disabled={!canSave}
          onClick={save}
        >
          Save
        </button>
      </div>
      {phase === "error" ? (
        <p className="settings-note" role="alert">
          That key couldn't be saved. Check it and try again.
        </p>
      ) : null}
    </Field>
  );
}

/**
 * The Spotify connect control (NIC-133): a "Connect Spotify" button that runs the OAuth flow on the
 * macOS host (`connectSpotify` — opens the browser, captures the redirect, stores tokens in the
 * Keychain), and a "Disconnect" that clears them (`deleteSecret`). Connection state comes from
 * `getSecretStatus("spotify_oauth")` — presence only, the tokens are never read back. Requires the
 * Spotify Client ID field above to be set; a connect without it fails with honest guidance.
 */
function SpotifyConnectField() {
  const bridge = useBridge();
  const [connected, setConnected] = useState<boolean | null>(null); // null while the status settles
  const [phase, setPhase] = useState<"idle" | "connecting" | "error">("idle");
  const [message, setMessage] = useState<string | null>(null);

  useEffect(() => {
    let active = true;
    void bridge
      .getSecretStatus({ reference: SPOTIFY_OAUTH_REFERENCE })
      .then((result) => {
        if (active) setConnected(result.bound);
      })
      .catch(() => {
        if (active) setConnected(false);
      });
    return () => {
      active = false;
    };
  }, [bridge]);

  function connect() {
    setPhase("connecting");
    setMessage(null);
    void bridge
      .connectSpotify()
      .then((result) => {
        if (result.connected) {
          setConnected(true);
          setPhase("idle");
        } else {
          setPhase("error");
          setMessage("Couldn't connect to Spotify. Please try again.");
        }
      })
      .catch((error: unknown) => {
        setPhase("error");
        setMessage(error instanceof Error ? error.message : "Couldn't connect to Spotify. Please try again.");
      });
  }

  function disconnect() {
    void bridge
      .deleteSecret({ reference: SPOTIFY_OAUTH_REFERENCE })
      .then(() => {
        setConnected(false);
        setPhase("idle");
        setMessage(null);
      })
      .catch(() => {
        // Leave the state as-is; a failed delete is rare and the next status read reconciles it.
      });
  }

  const statusLabel = connected === null ? "Checking…" : connected ? "Connected" : "Not connected";

  return (
    <Field
      label="Spotify account"
      hint="Connect Spotify to show your now-playing track (and controls) on the Entertainment dashboard. Uses the Client ID above; opens your browser to sign in. Tokens are stored in your macOS Keychain — never in config or logs."
    >
      <div className="settings-secret">
        <span className="settings-secret__status" data-bound={connected === true}>
          {statusLabel}
        </span>
        {connected ? (
          <button type="button" className="settings-button" onClick={disconnect}>
            Disconnect
          </button>
        ) : (
          <button
            type="button"
            className="settings-button settings-button--primary"
            disabled={phase === "connecting"}
            onClick={connect}
          >
            {phase === "connecting" ? "Connecting…" : "Connect Spotify"}
          </button>
        )}
      </div>
      {phase === "error" && message ? (
        <p className="settings-note" role="alert">
          {message}
        </p>
      ) : null}
    </Field>
  );
}

/** The logical name pattern a ticker symbol must match (NIC-128) — mirrors the settings-patch
 *  contract. Uppercased on entry; the store normalizes again on write. */
const TICKER_INPUT_PATTERN = /^[A-Za-z][A-Za-z0-9.-]{0,9}$/;
const TICKERS_MAX = 20;

function tickersEqual(a: readonly string[], b: readonly string[]): boolean {
  return a.length === b.length && a.every((symbol, index) => symbol === b[index]);
}

/**
 * The Executive Stocks widget's ticker list (NIC-128): the user's tracked symbols, edited as
 * add/remove chips and persisted through the validated settings path (`stocks.tickers`). Seeds
 * from the resolved snapshot (the shipped starter list until the user changes it); an empty list
 * is a real state — the widget then shows its "add tickers" prompt. Symbols are uppercased and
 * deduped on entry (the store normalizes again on write), and the contract caps the list at 20.
 */
function StocksTickersField() {
  const { snapshot } = useSettingsSnapshot();
  const updateSettings = useUpdateSettings();

  const [baseline, setBaseline] = useState<readonly string[]>(snapshot?.stocks?.tickers ?? []);
  const [draft, setDraft] = useState<string[]>([...(snapshot?.stocks?.tickers ?? [])]);
  const [input, setInput] = useState("");

  const candidate = input.trim().toUpperCase();
  const canAdd =
    TICKER_INPUT_PATTERN.test(candidate) && !draft.includes(candidate) && draft.length < TICKERS_MAX;
  const dirty = !tickersEqual(draft, baseline);

  function add() {
    if (!canAdd) return;
    setDraft((prev) => [...prev, candidate]);
    setInput("");
  }
  function remove(symbol: string) {
    setDraft((prev) => prev.filter((entry) => entry !== symbol));
  }
  function save() {
    void updateSettings({ stocks: { tickers: draft } });
    setBaseline([...draft]);
  }
  function cancel() {
    setDraft([...baseline]);
    setInput("");
  }

  return (
    <Field
      label="Tracked tickers"
      hint="Symbols shown in the Executive Stocks widget, four to a page. Uppercased automatically; up to 20."
    >
      <div className="settings-tickers">
        <ul className="settings-tickers__list">
          {draft.length === 0 ? (
            <li className="settings-tickers__empty">No tickers yet — the widget shows an add prompt.</li>
          ) : (
            draft.map((symbol) => (
              <li key={symbol} className="settings-tickers__chip">
                <span>{symbol}</span>
                <button
                  type="button"
                  className="settings-tickers__remove"
                  aria-label={`Remove ${symbol}`}
                  onClick={() => remove(symbol)}
                >
                  ×
                </button>
              </li>
            ))
          )}
        </ul>
        <div className="settings-tickers__add">
          <input
            type="text"
            className="settings-input"
            value={input}
            placeholder="Add a symbol, e.g. TSLA"
            aria-label="Add a stock ticker"
            autoComplete="off"
            maxLength={10}
            onChange={(event) => setInput(event.target.value)}
            onKeyDown={(event) => {
              if (event.key === "Enter") {
                event.preventDefault();
                add();
              }
            }}
          />
          <button type="button" className="settings-button" disabled={!canAdd} onClick={add}>
            Add
          </button>
        </div>
        <div className="settings-tickers__actions">
          <button
            type="button"
            className="settings-button settings-button--ghost"
            disabled={!dirty}
            onClick={cancel}
          >
            Cancel
          </button>
          <button
            type="button"
            className="settings-button settings-button--primary"
            disabled={!dirty}
            onClick={save}
          >
            Save
          </button>
        </div>
      </div>
    </Field>
  );
}

/** Maps each of the user's calendars to a mode (NIC-126), so the Today panel shows the right events
 *  per mode. Reads the calendar list from the host (requesting Calendar access at point of use) and
 *  the current map from the settings snapshot; a change writes the whole `calendarModeMap` through
 *  the settings path. "Unassigned" removes the mapping — those events fall under Executive. */
function CalendarModeMapField() {
  const bridge = useBridge();
  const { snapshot } = useSettingsSnapshot();
  const updateSettings = useUpdateSettings();
  const [calendars, setCalendars] = useState<readonly CalendarInfo[] | null>(null); // null while loading
  const [authorized, setAuthorized] = useState(true);

  useEffect(() => {
    let active = true;
    void bridge
      .listCalendars()
      .then((result) => {
        if (!active) return;
        setCalendars(result.calendars);
        setAuthorized(result.authorized);
      })
      .catch(() => {
        if (!active) return;
        setCalendars([]);
        setAuthorized(false);
      });
    return () => {
      active = false;
    };
  }, [bridge]);

  const map = snapshot?.calendarModeMap ?? {};

  function assign(calendarId: string, mode: string) {
    const next: Record<string, string> = { ...map };
    if (mode === "") {
      delete next[calendarId];
    } else {
      next[calendarId] = mode;
    }
    void updateSettings({ calendarModeMap: next });
  }

  return (
    <Field
      label="Calendar → mode"
      hint="Map each calendar to a mode so the Today panel shows the right events per mode. Unmapped calendars show under Executive. Tip: add #executive, #developer, #school, or #entertainment to an event's notes to override per event."
    >
      {calendars === null ? (
        <span className="settings-secret__status">Checking…</span>
      ) : !authorized ? (
        <Unavailable label="Grant Calendar access to map your calendars (System Settings → Privacy & Security → Calendars)." />
      ) : calendars.length === 0 ? (
        <span className="settings-calendars__empty">No calendars found.</span>
      ) : (
        <ul className="settings-calendars">
          {calendars.map((calendar) => (
            <li key={calendar.id} className="settings-calendars__row">
              <span
                className="settings-calendars__swatch"
                style={calendar.colorHex ? { background: calendar.colorHex } : undefined}
                aria-hidden="true"
              />
              <span className="settings-calendars__title">{calendar.title}</span>
              <select
                className="settings-select"
                value={map[calendar.id] ?? ""}
                onChange={(event) => assign(calendar.id, event.target.value)}
                aria-label={`Mode for ${calendar.title}`}
              >
                <option value="">Unassigned</option>
                {MODE_IDS.map((mode) => (
                  <option key={mode} value={mode}>
                    {humanizeId(mode)}
                  </option>
                ))}
              </select>
            </li>
          ))}
        </ul>
      )}
    </Field>
  );
}

/** A coarse "data age" label from an ISO instant: "just now" / "Nm ago" / "Nh ago" / "Nd ago". */
function formatScrapeAge(iso: string): string {
  const elapsedMs = Date.now() - new Date(iso).getTime();
  if (!Number.isFinite(elapsedMs) || elapsedMs < 60_000) return "just now";
  const minutes = Math.floor(elapsedMs / 60_000);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  return `${Math.floor(hours / 24)}d ago`;
}

/** "4 courses, 7 deadlines" — singular/plural, never a fabricated count. */
function scrapeCountsLabel(status: CanvasStatus): string {
  const courses = `${status.courseCount} ${status.courseCount === 1 ? "course" : "courses"}`;
  const deadlines = `${status.deadlineCount} ${status.deadlineCount === 1 ? "deadline" : "deadlines"}`;
  return `${courses}, ${deadlines}`;
}

/**
 * The Canvas connect card (NIC-132): pairs the Chrome extension with the local ingest endpoint. The
 * School Deadlines/Courses widgets are fed by a scrape the extension posts here on Canvas visits, so
 * this shows the endpoint + token to paste into the extension, the last scrape's age/counts, and a
 * Disconnect that purges the scraped data and rotates the token (the old token stops working). Off
 * the macOS host the surface reports unavailable rather than a broken pairing panel.
 */
function CanvasConnectField() {
  const bridge = useBridge();
  const [status, setStatus] = useState<CanvasStatus | null>(null); // null while loading
  const [copied, setCopied] = useState(false);

  useEffect(() => {
    let active = true;
    void bridge
      .getCanvasStatus()
      .then((result) => {
        if (active) setStatus(result);
      })
      .catch(() => {
        if (active) {
          setStatus({
            available: false, endpoint: "", token: null, lastScrapedAt: null,
            courseCount: 0, deadlineCount: 0, courses: [], deadlines: []
          });
        }
      });
    return () => {
      active = false;
    };
  }, [bridge]);

  function disconnect() {
    void bridge
      .resetCanvas()
      .then((result) => setStatus(result))
      .catch(() => {
        // Leave the state as-is; the next status read reconciles it.
      });
  }

  function toggleHidden(id: string, hidden: boolean) {
    void bridge
      .setCanvasItemHidden(id, hidden)
      .then((result) => setStatus(result))
      .catch(() => {
        // Leave the state as-is; the next status read reconciles it.
      });
  }

  const itemList = (title: string, items: readonly CanvasStatusItem[]) =>
    items.length > 0 ? (
      <div className="settings-canvas__group">
        <span className="settings-canvas__group-title">{title}</span>
        <ul className="settings-canvas__items">
          {items.map((item) => (
            <li
              key={item.id}
              className={`settings-canvas__item${item.hidden ? " settings-canvas__item--hidden" : ""}`}
            >
              <span className="settings-canvas__item-label">{item.label}</span>
              <button
                type="button"
                className="settings-button settings-button--ghost"
                onClick={() => toggleHidden(item.id, !item.hidden)}
                aria-label={`${item.hidden ? "Unhide" : "Hide"} ${item.label}`}
              >
                {item.hidden ? "Unhide" : "Hide"}
              </button>
            </li>
          ))}
        </ul>
      </div>
    ) : null;

  function copyToken() {
    if (!status?.token) return;
    void navigator.clipboard
      ?.writeText(status.token)
      .then(() => {
        setCopied(true);
        window.setTimeout(() => setCopied(false), 1500);
      })
      .catch(() => {
        // Clipboard denied — the token is still shown for manual copy.
      });
  }

  return (
    <Field
      label="Canvas (School widgets)"
      hint="The School Deadlines & Courses widgets are fed by a Chrome extension that scrapes Canvas on your visits and posts to this local endpoint. Pair the extension with the endpoint and token below. Scraped data stays on this Mac. Disconnect clears it and rotates the token — you'll need to re-pair."
    >
      {status === null ? (
        <span className="settings-secret__status">Checking…</span>
      ) : !status.available ? (
        <Unavailable label="Requires the macOS host" />
      ) : (
        <div className="settings-canvas">
          <div className="settings-canvas__pair">
            <span className="settings-canvas__label">Endpoint</span>
            <code className="settings-canvas__value">{status.endpoint}</code>
          </div>
          <div className="settings-canvas__pair">
            <span className="settings-canvas__label">Token</span>
            <code className="settings-canvas__value settings-canvas__token">{status.token ?? "—"}</code>
            <button type="button" className="settings-button" onClick={copyToken} disabled={!status.token}>
              {copied ? "Copied" : "Copy"}
            </button>
          </div>
          <p className="settings-canvas__status">
            {status.lastScrapedAt
              ? `Last synced ${formatScrapeAge(status.lastScrapedAt)} · ${scrapeCountsLabel(status)}`
              : "No scrape received yet — open Canvas in Chrome with the extension installed."}
          </p>
          {itemList("Courses", status.courses)}
          {itemList("Deadlines", status.deadlines)}
          <button type="button" className="settings-button" onClick={disconnect}>
            Disconnect
          </button>
        </div>
      )}
    </Field>
  );
}

function SetupPanel() {
  // The knowledge-root control seeds from the persisted read (NIC-141).
  const { status } = useSettingsSnapshot();
  return status === "loading" ? <SettingsLoading /> : <SetupPanelBody />;
}

function SetupPanelBody() {
  const { snapshot } = useSettingsSnapshot();
  const updateSettings = useUpdateSettings();
  // The native NSOpenPanel picker is a macOS-host concern (off the versioned bridge);
  // in a plain browser there is no channel, so the Browse button is honest-disabled.
  const canBrowse = isShellControlAvailable();

  const [baselineRoot, setBaselineRoot] = useState(snapshot?.knowledge.rootReference ?? "");
  const [draftRoot, setDraftRoot] = useState(baselineRoot);
  const dirty = draftRoot.trim() !== baselineRoot && draftRoot.trim().length > 0;

  // The native shell posts back the folder chosen in the Finder picker (NIC-138): it stages
  // into the draft, and Save persists it through the validated settings path.
  useEffect(() => {
    const target = window as KnowledgeRootWindow;
    target.__cerebralKnowledgeRootUpdate = (path: string) => setDraftRoot(path);
    return () => {
      delete target.__cerebralKnowledgeRootUpdate;
    };
  }, []);

  function save() {
    const trimmed = draftRoot.trim();
    if (!trimmed) {
      return;
    }
    void updateSettings({ knowledge: { rootReference: trimmed } });
    setDraftRoot(trimmed);
    setBaselineRoot(trimmed);
  }
  function cancel() {
    setDraftRoot(baselineRoot);
  }

  return (
    <>
      <Section title="Knowledge root">
        <Field
          label="Root folder"
          hint="Where durable Markdown knowledge lives. Choose a folder, or type a path, then Save. Changing it re-points to the new location — it never moves or deletes what is already there. Applies on next launch."
        >
          <div className="settings-root-picker">
            <input
              type="text"
              className="settings-input"
              value={draftRoot}
              placeholder="e.g. ~/CerebralHelm/knowledge"
              aria-label="Knowledge root reference"
              onChange={(event) => setDraftRoot(event.target.value)}
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
        <SectionActions dirty={dirty} onSave={save} onCancel={cancel} />
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
        <ProviderKeyField
          reference={TMDB_SECRET_REFERENCE}
          label="TMDB API key"
          hint="Powers the Entertainment Releases widget. Stored in your macOS Keychain — never in config or logs. Get a free key at themoviedb.org."
          placeholder="Paste your TMDB API key"
        />
        <ProviderKeyField
          reference={FINNHUB_SECRET_REFERENCE}
          label="Finnhub API key"
          hint="Powers the Executive Stocks widget. Stored in your macOS Keychain — never in config or logs. Get a free key at finnhub.io."
          placeholder="Paste your Finnhub API key"
        />
        <ProviderKeyField
          reference={NEWSDATA_SECRET_REFERENCE}
          label="NewsData API key"
          hint="Powers the News panel on every mode. Stored in your macOS Keychain — never in config or logs. Get a free key at newsdata.io."
          placeholder="Paste your NewsData API key"
        />
        <ProviderKeyField
          reference={GITHUB_SECRET_REFERENCE}
          label="GitHub personal access token"
          hint="Powers the Developer Project Git Status widget (read-only: pull requests, Actions, commits). Stored in your macOS Keychain — never in config or logs. Create a fine-grained token at github.com/settings/tokens."
          placeholder="Paste your GitHub token"
        />
        <ProviderKeyField
          reference={SPOTIFY_CLIENT_ID_REFERENCE}
          label="Spotify Client ID"
          hint="Powers the Entertainment Spotify widget. Create an app at developer.spotify.com and add the redirect URI http://127.0.0.1:8888/callback — then paste its Client ID here. Public, but stored in your macOS Keychain."
          placeholder="Paste your Spotify Client ID"
        />
        <SpotifyConnectField />
        <StocksTickersField />
        <CalendarModeMapField />
        <CanvasConnectField />
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
