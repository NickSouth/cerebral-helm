import type { DashboardBootstrapState } from "./types";
import type {
  AppReference,
  BridgeEvent,
  BridgeEventListener,
  CerebralBridge,
  ChromeProfile,
  LayoutSession,
  RecentActivity,
  SettingsSnapshot,
  Unsubscribe,
  UrlReference
} from "./cerebralBridge";
import {
  getDashboardConfigBundle,
  getDashboardFixture,
  failureStateFixtures
} from "../fixtures/canonicalFixtures";
import {
  capabilityBridgeEvent,
  confirmationBridgeEvent,
  lifecycleBridgeEvents
} from "./eventFixtures";
import { validateSettingsChanges } from "../shell/settings/settingsPatch";
import recentActivityResponse from "../../../../packages/contracts/fixtures/valid/bridge/operations/get-recent-activity-response.json";

/** Executive is the default mode (config/defaults/app.json `defaultModeId`; ADR-007). */
const DEFAULT_BOOTSTRAP_KEY = "mode.executive.ready";

const RECENT_ACTIVITY = (recentActivityResponse.payload as { recentActivity: RecentActivity })
  .recentActivity;

/** Compose a full bootstrap state from the eager config bundle and a per-state snapshot. */
function composeBootstrapState(canonicalKey: string): DashboardBootstrapState {
  return {
    ...getDashboardConfigBundle(),
    ...getDashboardFixture(canonicalKey)
  };
}

/**
 * The static seed used by the pre-bridge state store. NIC-52 B2 replaces the static store
 * with one backed by `createMockCerebralBridge()` without changing consumers. A caller may
 * seed a non-default canonical state (e.g. a degraded state for preview/tests — NIC-64).
 */
export function loadBootstrapState(
  bootstrapKey: string = DEFAULT_BOOTSTRAP_KEY
): DashboardBootstrapState {
  return composeBootstrapState(bootstrapKey);
}

/**
 * A `CerebralBridge` plus replay controls so stories and tests can drive the canonical
 * lifecycle and failure fixtures through the same contract the components consume.
 */
export interface MockCerebralBridge extends CerebralBridge {
  /** Emit one event to all current subscribers. */
  emit(event: BridgeEvent): void;
  /** Replay every canonical command-lifecycle transition as bridge events. */
  replayLifecycle(): void;
  /** Replay the capability change plus every canonical failure / degraded state. */
  replayFailures(): void;
  /** Surface the canonical policy-owned confirmation (a `confirmation.changed` disclosure). */
  replayConfirmation(): void;
}

/** Fold an accepted settings-patch `changes` delta into a snapshot — the mock's stand-in for
 *  the store's merge, so getSettings + settings.changed reflect writes (NIC-137). */
function mergeSettingsChanges(
  prev: SettingsSnapshot,
  changes: Record<string, unknown>
): SettingsSnapshot {
  const appearance = changes.appearance as { reducedMotion?: unknown; assistantName?: unknown } | undefined;
  const knowledge = changes.knowledge as { rootReference?: unknown } | undefined;
  const workspace = changes.workspace as {
    windowsStoredByMode?: unknown;
    mainDisplayId?: unknown;
    layoutDisplayId?: unknown;
  } | undefined;
  return {
    schemaVersion: prev.schemaVersion,
    defaultModeId: typeof changes.defaultModeId === "string" ? changes.defaultModeId : prev.defaultModeId,
    confirmAllActions:
      typeof changes.confirmAllActions === "boolean" ? changes.confirmAllActions : prev.confirmAllActions,
    appearance: {
      reducedMotion:
        typeof appearance?.reducedMotion === "boolean" ? appearance.reducedMotion : prev.appearance.reducedMotion,
      assistantName:
        typeof appearance?.assistantName === "string" ? appearance.assistantName : prev.appearance.assistantName
    },
    knowledge: {
      rootReference:
        typeof knowledge?.rootReference === "string" ? knowledge.rootReference : prev.knowledge.rootReference
    },
    workspace: {
      windowsStoredByMode:
        typeof workspace?.windowsStoredByMode === "boolean"
          ? workspace.windowsStoredByMode
          : prev.workspace.windowsStoredByMode,
      mainDisplayId:
        typeof workspace?.mainDisplayId === "string" ? workspace.mainDisplayId : prev.workspace.mainDisplayId,
      layoutDisplayId:
        typeof workspace?.layoutDisplayId === "string"
          ? workspace.layoutDisplayId
          : prev.workspace.layoutDisplayId
    },
    modeColors:
      changes.modeColors && typeof changes.modeColors === "object"
        ? (changes.modeColors as Record<string, string>)
        : prev.modeColors,
    stocks:
      changes.stocks &&
      typeof changes.stocks === "object" &&
      Array.isArray((changes.stocks as { tickers?: unknown }).tickers)
        ? { tickers: (changes.stocks as { tickers: string[] }).tickers }
        : prev.stocks
  };
}

/** Slug a label to a config id (mirrors the Swift `UserAppReferences.slug` grammar closely
 *  enough for browser previews/tests): lowercase, non-alphanumerics collapse to dashes, and
 *  a leading digit/empty gets a letter stem. */
function slugId(label: string): string {
  const slug = label
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "");
  return /^[a-z][a-z0-9-]*$/.test(slug) ? slug : `link-${slug}`.replace(/-+$/g, "") || "link";
}

/** The mock's stand-in for the bridge's `addUrlReference` minting (NIC-146/151): http/https
 *  only, scheme-less host defaults to https, an optional Chrome profile (blank → none,
 *  validated), idempotent by (target, profile), id unique across `taken`. Mirrors the
 *  Swift `UserURLReferences.add`. */
function mintUrlReference(
  rawUrl: string,
  label: string | undefined,
  profile: string | undefined,
  existing: readonly UrlReference[]
): { reference: UrlReference | null; error?: string } {
  const trimmed = rawUrl.trim();
  if (!trimmed) {
    return { reference: null, error: "Enter a URL to add." };
  }
  // A blank profile is "no profile"; a non-blank one must match the reference-catalog
  // pattern so it cannot smuggle extra `--profile-directory` flags (NIC-151).
  const trimmedProfile = profile?.trim();
  const normalizedProfile = trimmedProfile ? trimmedProfile : undefined;
  if (normalizedProfile && !/^[A-Za-z0-9 ._-]+$/.test(normalizedProfile)) {
    return {
      reference: null,
      error:
        "The Chrome profile can only contain letters, numbers, spaces, dots, hyphens, and underscores."
    };
  }
  const candidate = /^[a-z][a-z0-9+.-]*:/i.test(trimmed) ? trimmed : `https://${trimmed}`;
  let parsed: URL;
  try {
    parsed = new URL(candidate);
  } catch {
    return { reference: null, error: "That doesn't look like a valid web address." };
  }
  if (parsed.protocol !== "http:" && parsed.protocol !== "https:") {
    return { reference: null, error: "Only http and https web addresses can be added." };
  }
  const existingMatch = existing.find(
    (url) => url.target === candidate && url.profile === normalizedProfile
  );
  if (existingMatch) {
    return { reference: existingMatch };
  }
  const labelText = label?.trim() || parsed.hostname;
  const taken = new Set(existing.map((url) => url.id));
  let id = slugId(labelText);
  if (taken.has(id)) {
    let counter = 2;
    while (taken.has(`${id}-${counter}`)) {
      counter += 1;
    }
    id = `${id}-${counter}`;
  }
  return {
    reference: { id, label: labelText, target: candidate, ...(normalizedProfile ? { profile: normalizedProfile } : {}) }
  };
}

/** The layout a mode opens in browser previews / tests (NIC-142). Mirrors the
 *  shipped `config/modes/developer.json` layout — Developer is the only mode that
 *  ships an authored layout, so every other mode honestly has none. */
function mockLayoutSession(modeId: string): LayoutSession | null {
  if (modeId !== "developer") {
    return null;
  }
  return {
    modeId,
    windows: [{ ref: "claude-desktop", kind: "app", label: "Claude" }],
    quickToggle: {
      activeRef: "vscode",
      targets: [
        { ref: "vscode", kind: "app", label: "Visual Studio Code" },
        { ref: "github", kind: "url", label: "GitHub" }
      ]
    }
  };
}

/** Reference-id → display label for mock pins (mirrors the mock's listApps names). */
function mockRefLabel(ref: string): string {
  const labels: Record<string, string> = {
    terminal: "Terminal",
    vscode: "Visual Studio Code",
    "claude-desktop": "Claude",
    github: "GitHub"
  };
  return labels[ref] ?? ref;
}

export function createMockCerebralBridge(
  options: { bootstrapKey?: string } = {}
): MockCerebralBridge {
  const bootstrapKey = options.bootstrapKey ?? DEFAULT_BOOTSTRAP_KEY;
  const listeners = new Set<BridgeEventListener>();
  // The active layout session (NIC-142), held mutably so toggleLayout can swap the
  // dynamic slot and re-broadcast, mirroring the real bridge.
  let activeLayout: LayoutSession | null = null;
  // Session-only per-mode collapse-all state (NIC-143), so a browser preview can flip
  // the bottom-bar collapse/expand icon; the real bridge hides/returns the windows.
  const collapsedModes = new Set<string>();
  // A mutable window inventory for the navigator (NIC-143), so a browser preview can
  // minimize/surface/close and see the change on the next listWindows; the real bridge
  // enumerates and acts on live windows via Accessibility.
  const windowGroups: {
    bundleId: string;
    appName: string;
    windows: { id: string; title: string; minimized: boolean }[];
  }[] = [
    {
      bundleId: "com.google.Chrome",
      appName: "Google Chrome",
      windows: [
        { id: "1001", title: "Inbox — Gmail", minimized: false },
        { id: "1002", title: "CerebralHelm · GitHub", minimized: true }
      ]
    },
    {
      bundleId: "com.microsoft.VSCode",
      appName: "Visual Studio Code",
      windows: [{ id: "2001", title: "BridgeSession.swift — cerebral-helm", minimized: false }]
    }
  ];
  const findWindow = (id: string) => {
    for (const group of windowGroups) {
      const window = group.windows.find((candidate) => candidate.id === id);
      if (window) {
        return { group, window };
      }
    }
    return null;
  };
  // Representative persisted settings, held mutably so updateSettings visibly persists +
  // broadcasts a settings.changed event (mirrors the real bridge; NIC-141/137).
  let settingsSnapshot: SettingsSnapshot = {
    schemaVersion: "1.0.0",
    defaultModeId: "developer",
    confirmAllActions: false,
    appearance: { reducedMotion: false, assistantName: "Heimlich" },
    knowledge: { rootReference: "knowledge-root" },
    workspace: { windowsStoredByMode: true, mainDisplayId: "system-primary", layoutDisplayId: "system-primary" },
    modeColors: {},
    stocks: { tickers: ["SPY", "AAPL", "NVDA", "VTI"] }
  };
  let settingsEventSeq = 0;
  // The bound secret references (NIC-134), held mutably so storeSecret visibly binds one and
  // getSecretStatus reflects it — the browser stand-in for the Keychain. Values are never kept
  // (the mock only tracks presence), mirroring the presence-only surface the real bridge exposes.
  const boundSecrets = new Set<string>();
  // The configured URL references (NIC-146), held mutably so addUrlReference visibly
  // mints and listUrls reflects it — the browser stand-in for the user URL catalog.
  // Seeded with the shipped config/references/urls.json entries.
  // github carries a favicon (the browser stand-in for a fetched icon, NIC-147);
  // docs has none, so its tile shows the globe placeholder.
  let urlReferences: UrlReference[] = [
    {
      id: "github",
      label: "GitHub",
      target: "https://github.com",
      iconPng:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    },
    { id: "docs", label: "Project Docs", target: "https://docs.cerebralhelm.local" }
  ];

  // The user's Chrome profiles (NIC-151), the browser stand-in for what the Mac
  // adapter reads from Chrome's Local State. Personal carries a sample avatar.
  const chromeProfiles: ChromeProfile[] = [
    {
      directory: "Default",
      name: "Personal",
      iconPng:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    },
    { directory: "Profile 1", name: "Work" }
  ];
  // Pinned Chrome-profile app references, held mutably so addChromeProfileReference
  // visibly mints and listChromeProfiles reflects it (mirrors urlReferences).
  let chromeProfileRefs: AppReference[] = [];

  function emit(event: BridgeEvent): void {
    // Snapshot so a listener that unsubscribes mid-dispatch can't mutate the live set.
    for (const listener of [...listeners]) {
      listener(event);
    }
  }

  return {
    getBootstrapState() {
      return Promise.resolve(composeBootstrapState(bootstrapKey));
    },
    getRecentActivity() {
      return Promise.resolve(RECENT_ACTIVITY);
    },
    submitCommand(input) {
      // A `run <workflowId>` submission simulates the runtime's workflow execution
      // (NIC-85): a canned two-step progress sequence bracketed by lifecycle
      // transitions, so the progress renderer and store paths are exercisable in
      // the browser. It is visibly a simulation — the mock never claims a native
      // step actually ran.
      const workflowId = input.rawInput.startsWith("run ")
        ? input.rawInput.slice("run ".length).trim()
        : null;
      if (workflowId) {
        const commandId = "cmd_000000000000000000000002";
        const at = "2026-06-23T16:00:00.000Z";
        const progress = (
          actionId: string,
          status: string,
          index: number,
          suffix: string
        ): BridgeEvent => ({
          eventId: `brevt_run_${workflowId}_${suffix}`,
          type: "workflow.action.progress",
          schemaVersion: "1.0.0",
          timestamp: at,
          payload: {
            commandId,
            workflowId,
            actionId,
            kind: "mock.step",
            status,
            index,
            total: 2
          }
        });
        const lifecycle = (currentStatus: string): BridgeEvent => ({
          eventId: `brevt_run_${workflowId}_${currentStatus}`,
          type: "command.lifecycle.transition",
          schemaVersion: "1.0.0",
          timestamp: at,
          payload: { commandId, currentStatus }
        });
        // Staggered so the progress line is actually visible in the browser; the
        // sequence and payloads stay deterministic.
        emit(lifecycle("running"));
        emit(progress("step-one", "running", 1, "1r"));
        const later: ReadonlyArray<[BridgeEvent, number]> = [
          [progress("step-one", "succeeded", 1, "1s"), 400],
          [progress("step-two", "running", 2, "2r"), 500],
          [progress("step-two", "succeeded", 2, "2s"), 900],
          [lifecycle("succeeded"), 1000]
        ];
        for (const [event, delay] of later) {
          setTimeout(() => emit(event), delay);
        }
        return Promise.resolve({ commandId, accepted: true });
      }
      return Promise.resolve({ commandId: "cmd_000000000000000000000001", accepted: true });
    },
    applyMode(input) {
      // Eager config is already in state, so a switch needs no round-trip: emit the target
      // mode's resolved snapshot as a `config.changed` event the store folds in (the theme
      // re-themes via data-mode; the heavy region data resolves on switch).
      try {
        const snapshot = getDashboardFixture(`mode.${input.modeId}.ready`);
        emit({
          eventId: `brevt_applymode_${input.modeId}`,
          type: "config.changed",
          schemaVersion: "1.0.0",
          timestamp: "2026-06-23T16:00:00.000Z",
          payload: { snapshot }
        });
        return Promise.resolve({ modeId: input.modeId, status: "ok" as const });
      } catch {
        return Promise.resolve({ modeId: input.modeId, status: "error" as const });
      }
    },
    captureNote() {
      return Promise.resolve({ noteId: "note_000000000000000000000001" });
    },
    searchNotes() {
      return Promise.resolve({ results: [] });
    },
    decideConfirmation(input) {
      // The UI submits the decision; the bridge owns the resulting state change. Clearing the
      // active confirmation is an event, not a UI-local mutation (the real bridge would also
      // drive the command lifecycle forward) — keeps the surface event-driven and honest.
      emit({
        eventId: "brevt_confcleared01",
        type: "confirmation.changed",
        schemaVersion: "1.0.0",
        timestamp: "2026-06-23T16:00:45.000Z",
        payload: { confirmation: null }
      });
      return Promise.resolve({ confirmationId: input.id, decision: input.decision });
    },
    updateSettings(input) {
      // Stand in for the bridge's config validation path (FR-CFG-04): validate the patch's changes
      // against the settings-patch allowlist. A disallowed change (e.g. a risk override) is rejected
      // here exactly as the schema would reject it — the UI never gets a bespoke, weaker path.
      const changes = (input.patch as { changes?: unknown }).changes;
      const { valid } = validateSettingsChanges(changes);
      if (valid) {
        // Persist into the mutable snapshot and broadcast, mirroring the real bridge so a
        // Save visibly re-syncs every surface (assistant name, mode colors) live (NIC-137).
        settingsSnapshot = mergeSettingsChanges(settingsSnapshot, (changes as Record<string, unknown>) ?? {});
        settingsEventSeq += 1;
        emit({
          eventId: `brevt_settings${String(settingsEventSeq).padStart(8, "0")}`,
          type: "settings.changed",
          schemaVersion: "1.0.0",
          timestamp: "2026-07-10T16:00:00.000Z",
          payload: { settings: settingsSnapshot }
        });
      }
      return Promise.resolve({ accepted: valid });
    },
    getSettings() {
      // The mutable snapshot (seeded with representative non-defaults) so browser previews prove
      // the settings UI reads stored state and reflects saves (NIC-141/137).
      return Promise.resolve(settingsSnapshot);
    },
    storeSecret(input) {
      // The browser stand-in for the Keychain write (NIC-134): a non-empty value binds the
      // reference. The value is not retained — only presence — mirroring the real surface.
      const stored = input.value.trim().length > 0;
      if (stored) {
        boundSecrets.add(input.reference);
      }
      return Promise.resolve({ reference: input.reference, stored });
    },
    getSecretStatus(input) {
      return Promise.resolve({ reference: input.reference, bound: boundSecrets.has(input.reference) });
    },
    listApps() {
      // A representative installed-app set for browser previews of the More Apps
      // picker (NIC-119). No icons — the honest non-Mac fallback glyph renders.
      // `referenceId` mirrors the bridge's join onto configured app references:
      // only reference-backed apps are pinnable.
      return Promise.resolve({
        apps: [
          { bundleId: "com.apple.Safari", name: "Safari", referenceId: null },
          { bundleId: "com.apple.mail", name: "Mail", referenceId: null },
          { bundleId: "com.apple.Terminal", name: "Terminal", referenceId: "terminal" },
          { bundleId: "com.microsoft.VSCode", name: "Visual Studio Code", referenceId: "vscode" },
          { bundleId: "com.anthropic.claudefordesktop", name: "Claude", referenceId: "claude-desktop" }
        ],
        truncated: false
      });
    },
    updateQuickApps(input) {
      // Stand in for the validated override path (NIC-119c): the same
      // reference-existence check the bridge applies, accepted otherwise. A pinned
      // slot may name an app OR a URL reference (NIC-146) — both catalogs are valid.
      const known = new Set([
        "terminal",
        "vscode",
        "claude-desktop",
        "xcode",
        ...urlReferences.map((url) => url.id),
        ...chromeProfileRefs.map((ref) => ref.id)
      ]);
      const unknown = input.quickApps.filter((id) => !known.has(id));
      if (unknown.length > 0) {
        return Promise.resolve({
          accepted: false,
          quickApps: input.quickApps,
          errors: unknown.map((id) => `"${id}" is not a configured app or URL reference.`)
        });
      }
      // An accepted write emits mode.quickapps.changed, mirroring the native
      // bridge (NIC-149) — tiles refresh from the event, never optimistically.
      emit({
        eventId: "brevt_mock_quickapps_changed",
        type: "mode.quickapps.changed",
        schemaVersion: "1.0.0",
        timestamp: new Date().toISOString(),
        payload: { modeId: input.modeId, quickApps: [...input.quickApps] }
      });
      return Promise.resolve({ accepted: true, quickApps: input.quickApps, errors: [] });
    },
    addUrlReference(input) {
      // Mirror the bridge's minting (NIC-146/151): http/https only, an optional Chrome
      // profile, idempotent by (target, profile). An accepted add persists into the
      // mutable catalog so listUrls reflects it and the freshly minted id can pin
      // through updateQuickApps this same session.
      const { reference, error } = mintUrlReference(input.url, input.label, input.profile, urlReferences);
      if (!reference) {
        return Promise.resolve({ accepted: false, reference: null, errors: [error ?? "The URL could not be added."] });
      }
      if (!urlReferences.some((url) => url.id === reference.id)) {
        urlReferences = [...urlReferences, reference];
      }
      return Promise.resolve({ accepted: true, reference, errors: [] });
    },
    listUrls() {
      // The configured URL references, sorted by label like the bridge (NIC-146).
      const sorted = [...urlReferences].sort((a, b) => a.label.localeCompare(b.label));
      return Promise.resolve({ urls: sorted });
    },
    listChromeProfiles() {
      // Discovered profiles + the pinned Chrome-profile references (NIC-151).
      return Promise.resolve({
        profiles: [...chromeProfiles],
        references: [...chromeProfileRefs].sort((a, b) => a.label.localeCompare(b.label))
      });
    },
    addChromeProfileReference(input) {
      // Mirror the bridge: mint an app reference opening Chrome in the chosen
      // profile, idempotent by directory, so listChromeProfiles reflects it and the
      // returned id pins through updateQuickApps this same session (NIC-151).
      const directory = input.directory.trim();
      if (!directory) {
        return Promise.resolve({ accepted: false, reference: null, errors: ["Choose a Chrome profile to pin."] });
      }
      const existing = chromeProfileRefs.find((ref) => ref.profile === directory);
      if (existing) {
        return Promise.resolve({ accepted: true, reference: existing, errors: [] });
      }
      const name = input.name?.trim() || directory;
      const taken = new Set([...chromeProfileRefs, ...urlReferences].map((ref) => ref.id));
      let id = slugId(`chrome-${name}`);
      if (taken.has(id)) {
        let counter = 2;
        while (taken.has(`${id}-${counter}`)) counter += 1;
        id = `${id}-${counter}`;
      }
      const reference: AppReference = { id, label: `Chrome — ${name}`, target: "com.google.Chrome", profile: directory };
      chromeProfileRefs = [...chromeProfileRefs, reference];
      return Promise.resolve({ accepted: true, reference, errors: [] });
    },
    runSpeedTest() {
      // A representative measurement for browser previews (NIC-135). The short
      // delay lets the widget's progress ring animate the way the ~30s native
      // run would; the real bridge resolves when networkQuality completes.
      return new Promise((resolve) => {
        setTimeout(
          () => resolve({ status: "ok", downloadMbps: 243.7, uploadMbps: 17.9, testedAt: new Date().toISOString() }),
          2600
        );
      });
    },
    openLayout(input) {
      // Mirror the bridge (NIC-142): a mode with an authored layout starts a
      // session delivered as a layout.session.changed event; a mode without one is
      // an honest rejection. Only Developer ships a layout in the mock fixtures.
      const session = mockLayoutSession(input.modeId);
      if (!session) {
        return Promise.resolve({ accepted: false, modeId: input.modeId });
      }
      activeLayout = session;
      emit({
        eventId: "brevt_mock_layout_open01",
        type: "layout.session.changed",
        schemaVersion: "1.0.0",
        timestamp: new Date().toISOString(),
        payload: { session }
      });
      return Promise.resolve({ accepted: true, modeId: input.modeId });
    },
    closeLayout() {
      activeLayout = null;
      emit({
        eventId: "brevt_mock_layout_close1",
        type: "layout.session.changed",
        schemaVersion: "1.0.0",
        timestamp: new Date().toISOString(),
        payload: { session: null }
      });
      return Promise.resolve({ closed: true });
    },
    toggleLayout(input) {
      // Swap the dynamic slot to the pressed target and re-broadcast (NIC-142). An
      // unknown target — or no active layout — is an honest rejection.
      const toggle = activeLayout?.quickToggle;
      if (!activeLayout || !toggle || !toggle.targets.some((target) => target.ref === input.ref)) {
        return Promise.resolve({ accepted: false });
      }
      activeLayout = {
        ...activeLayout,
        quickToggle: { ...toggle, activeRef: input.ref }
      };
      emit({
        eventId: "brevt_mock_layout_toggle",
        type: "layout.session.changed",
        schemaVersion: "1.0.0",
        timestamp: new Date().toISOString(),
        payload: { session: activeLayout }
      });
      return Promise.resolve({ accepted: true });
    },
    pinLayoutWindow(input) {
      // Append the reference as a new quick-toggle target and re-broadcast (NIC-142),
      // mirroring the bridge's validated override write.
      const toggle = activeLayout?.quickToggle;
      if (!activeLayout || !toggle) {
        return Promise.resolve({ accepted: false, errors: ["This layout has no dynamic slot."] });
      }
      if (!toggle.targets.some((target) => target.ref === input.ref)) {
        activeLayout = {
          ...activeLayout,
          quickToggle: {
            ...toggle,
            targets: [...toggle.targets, { ref: input.ref, kind: "app", label: mockRefLabel(input.ref) }]
          }
        };
        emit({
          eventId: "brevt_mock_layout_pin01",
          type: "layout.session.changed",
          schemaVersion: "1.0.0",
          timestamp: new Date().toISOString(),
          payload: { session: activeLayout }
        });
      }
      return Promise.resolve({ accepted: true, errors: [] });
    },
    addLayoutTarget(input) {
      // Session-only "+" live add (NIC-142): append the reference to the active
      // session's dynamic slot and re-broadcast. No persistence (the mock never
      // writes overrides anyway) — the distinction from pinLayoutWindow is the op.
      const toggle = activeLayout?.quickToggle;
      if (!activeLayout || !toggle) {
        return Promise.resolve({ accepted: false });
      }
      if (!toggle.targets.some((target) => target.ref === input.ref)) {
        activeLayout = {
          ...activeLayout,
          quickToggle: {
            ...toggle,
            targets: [...toggle.targets, { ref: input.ref, kind: "app", label: mockRefLabel(input.ref) }]
          }
        };
        emit({
          eventId: "brevt_mock_layout_add01",
          type: "layout.session.changed",
          schemaVersion: "1.0.0",
          timestamp: new Date().toISOString(),
          payload: { session: activeLayout }
        });
      }
      return Promise.resolve({ accepted: true });
    },
    updateLayout() {
      // The settings editor's Save; the mock accepts a well-formed layout (NIC-142).
      return Promise.resolve({ accepted: true, errors: [] });
    },
    toggleModeCollapse(input) {
      // Flip the mode's collapse-all state and broadcast it, so a browser preview shows
      // the icon change (NIC-143). The real bridge hides/returns the actual windows.
      const collapsed = !collapsedModes.has(input.modeId);
      if (collapsed) {
        collapsedModes.add(input.modeId);
      } else {
        collapsedModes.delete(input.modeId);
      }
      emit({
        eventId: "brevt_mock_collapse01",
        type: "mode.windowcollapse.changed",
        schemaVersion: "1.0.0",
        timestamp: new Date().toISOString(),
        payload: { modeId: input.modeId, collapsed }
      });
      return Promise.resolve({ collapsed });
    },
    closeAllWindows() {
      // Destructive, confirmation-gated (NIC-143): the real bridge routes this through
      // the command bus + policy engine. The mock surfaces a representative destructive
      // disclosure so a browser preview shows the confirmation the user must approve —
      // approve/cancel flow through the same `decideConfirmation` path.
      const base = (confirmationBridgeEvent.payload as { confirmation: Record<string, unknown> })
        .confirmation;
      emit({
        eventId: "brevt_mock_quitall0001",
        type: "confirmation.changed",
        schemaVersion: "1.0.0",
        timestamp: new Date().toISOString(),
        payload: {
          confirmation: {
            ...base,
            id: "conf_quitall00000000000000001",
            actionSummary: "Quit every open application across all modes.",
            risk: "destructive",
            reversibility: "not_reversible",
            policyReason: "Risk class 'destructive' requires confirmation.",
            destination: null,
            arguments: [],
            tool: {
              id: "apps.quitall",
              version: "1.0.0",
              purpose: "Quit every open application across all modes; graceful terminate."
            }
          }
        }
      });
      return Promise.resolve({ commandId: "cmd_quitall00000000000000001", accepted: true });
    },
    listWindows() {
      return Promise.resolve({
        apps: windowGroups.map((group) => ({
          ...group,
          windows: group.windows.map((window) => ({ ...window }))
        }))
      });
    },
    minimizeWindow(input) {
      const found = findWindow(input.windowId);
      if (found) {
        found.window.minimized = true;
      }
      return Promise.resolve({ ok: found !== null });
    },
    surfaceWindow(input) {
      const found = findWindow(input.windowId);
      if (found) {
        found.window.minimized = false;
      }
      return Promise.resolve({ ok: found !== null });
    },
    closeWindow(input) {
      const found = findWindow(input.windowId);
      if (found) {
        found.group.windows = found.group.windows.filter((window) => window.id !== input.windowId);
      }
      return Promise.resolve({ ok: found !== null });
    },
    captureLayout() {
      // A representative capture for browser previews of the authoring editor — the
      // real bridge snaps the currently-arranged windows to named frames.
      return Promise.resolve({
        windows: [
          { ref: "vscode", kind: "app", frame: "left-two-thirds" },
          { ref: "claude-desktop", kind: "app", frame: "right-third" }
        ]
      });
    },
    subscribe(listener): Unsubscribe {
      listeners.add(listener);
      return () => {
        listeners.delete(listener);
      };
    },
    emit,
    replayLifecycle() {
      for (const event of lifecycleBridgeEvents) {
        emit(event);
      }
    },
    replayFailures() {
      emit(capabilityBridgeEvent);
      for (const fixture of failureStateFixtures) {
        emit({
          eventId: `brevt_${fixture.id}`,
          type: "system.status.changed",
          schemaVersion: "1.0.0",
          timestamp: fixture.clock,
          payload: {
            canonicalKey: fixture.canonicalKey,
            category: fixture.category,
            state: fixture.state
          }
        });
      }
    },
    replayConfirmation() {
      emit(confirmationBridgeEvent);
    }
  };
}
