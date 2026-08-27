import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { resolvePaths } from "./workspace-roots.mjs";

function fail(message) {
  throw new Error(message);
}

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function assert(condition, message, errors) {
  if (!condition) {
    errors.push(message);
  }
}

function validateDefaults(document, relativePath, errors) {
  assert(typeof document.schemaVersion === "string", `${relativePath}: schemaVersion must be a string.`, errors);
  assert(typeof document.defaultModeId === "string", `${relativePath}: defaultModeId must be a string.`, errors);
  assert(Array.isArray(document.enabledAgentIds), `${relativePath}: enabledAgentIds must be an array.`, errors);
  assert(Array.isArray(document.enabledToolIds), `${relativePath}: enabledToolIds must be an array.`, errors);
}

// The registry of design-token names a config may reference lives with the UI that
// defines their values. Reading it here makes a dangling theme-token reference a
// build failure (the seed of the NIC-117 single reference-resolution gate).
export function readRegisteredModeThemeTokens(repositoryRoot) {
  const manifestPath = path.join(repositoryRoot, "apps", "dashboard", "src", "tokens", "tokens.manifest.json");
  const manifest = readJson(manifestPath);

  if (!Array.isArray(manifest.modeThemeTokens)) {
    fail(`${path.relative(repositoryRoot, manifestPath)}: modeThemeTokens must be an array.`);
  }

  return new Set(manifest.modeThemeTokens);
}

export function validateModeThemeTokens(document, relativePath, registeredTokenNames, errors) {
  const theme = document.theme;

  if (typeof theme !== "object" || theme === null || Array.isArray(theme)) {
    return;
  }

  for (const field of ["accentPrimary", "accentSecondary"]) {
    const tokenName = theme[field];

    if (typeof tokenName !== "string") {
      continue;
    }

    assert(
      registeredTokenNames.has(tokenName),
      `${relativePath}: theme.${field} "${tokenName}" must reference a registered design token (apps/dashboard/src/tokens/tokens.manifest.json).`,
      errors
    );
  }
}

// The widget registry lives with the UI that renders each slot (one component per id,
// never a per-mode conditional). Resolving widgets.left / widgets.right against it here
// makes a dangling widget reference a build failure — the same single reference gate as
// theme tokens (NIC-117 root decision).
export function readRegisteredWidgetIds(repositoryRoot) {
  const manifestPath = path.join(repositoryRoot, "apps", "dashboard", "src", "widgets", "widgets.manifest.json");
  const manifest = readJson(manifestPath);

  if (!Array.isArray(manifest.widgetIds)) {
    fail(`${path.relative(repositoryRoot, manifestPath)}: widgetIds must be an array.`);
  }

  return new Set(manifest.widgetIds);
}

export function validateModeWidgets(document, relativePath, registeredWidgetIds, errors) {
  const widgets = document.widgets;

  if (typeof widgets !== "object" || widgets === null || Array.isArray(widgets)) {
    return;
  }

  for (const side of ["left", "right"]) {
    const widgetId = widgets[side];

    if (typeof widgetId !== "string") {
      continue;
    }

    assert(
      registeredWidgetIds.has(widgetId),
      `${relativePath}: widgets.${side} "${widgetId}" must reference a registered widget (apps/dashboard/src/widgets/widgets.manifest.json).`,
      errors
    );
  }
}

// The pre-Mac application catalog is the resolution set for quick-app references. A
// configured app id that is not a known app is a typo/dangling reference (a build
// failure); runtime "not installed" is a separate, gracefully-degraded concern. On the
// Mac target the catalog is replaced by real app discovery.
export function readRegisteredQuickAppIds(repositoryRoot) {
  const manifestPath = path.join(repositoryRoot, "apps", "dashboard", "src", "appCatalog", "appCatalog.manifest.json");
  const manifest = readJson(manifestPath);

  if (!Array.isArray(manifest.appIds)) {
    fail(`${path.relative(repositoryRoot, manifestPath)}: appIds must be an array.`);
  }

  return new Set(manifest.appIds);
}

export function validateModeQuickApps(document, relativePath, registeredAppIds, errors) {
  const quickApps = document.quickApps;

  if (!Array.isArray(quickApps)) {
    return;
  }

  for (const appId of quickApps) {
    if (typeof appId !== "string") {
      continue;
    }

    assert(
      registeredAppIds.has(appId),
      `${relativePath}: quickApps entry "${appId}" must reference a registered application (apps/dashboard/src/appCatalog/appCatalog.manifest.json).`,
      errors
    );
  }
}

// A mode that carries an authored `layout` (NIC-142) provides its
// `open-<modeId>-layout` workflow by synthesis (WorkflowCatalogLoader), not as a
// static config/workflows/*.json file. Mirror that id-derivation here so the
// quick-action wiring gate resolves a layout-backed action the same way the Swift
// runtime does — without duplicating the step synthesis (only the id rule).
export function readLayoutBackedWorkflowIds(configRoot) {
  const modesDir = path.join(configRoot, "modes");
  const ids = new Set();

  if (!fs.existsSync(modesDir)) {
    return ids;
  }

  for (const file of fs.readdirSync(modesDir).filter((name) => name.endsWith(".json"))) {
    const mode = readJson(path.join(modesDir, file));
    if (mode.layout && typeof mode.id === "string") {
      ids.add(`open-${mode.id}-layout`);
    }
  }

  return ids;
}

// The quick-action dispatch registry is the single catalog of every planned action — its label,
// icon, archetype, and (only once built) the runtime target the dashboard dispatches it to. It
// lives with the UI that renders the slots. The gate runs both directions: an entry that declares
// a target must resolve it (a config/workflows/*.json id, a declared bridge handler, or a mode
// with a layout), and every id a mode configures must exist here — so a typo in a mode file is a
// build failure rather than a mystery button. An entry with no target is planned-not-built and
// renders as a labelled, disabled slot.
export const QUICK_ACTION_ARCHETYPES = new Set(["report", "input", "picker", "fire-and-forget"]);
export const QUICK_ACTION_TONES = new Set(["danger"]);

export function readQuickActionRegistry(repositoryRoot) {
  const registryPath = path.join(repositoryRoot, "apps", "dashboard", "src", "shell", "quickActions.registry.json");
  const registry = readJson(registryPath);
  const relativePath = path.relative(repositoryRoot, registryPath);

  if (!Array.isArray(registry.handlers)) {
    fail(`${relativePath}: handlers must be an array.`);
  }

  if (typeof registry.actions !== "object" || registry.actions === null || Array.isArray(registry.actions)) {
    fail(`${relativePath}: actions must be an object.`);
  }

  return {
    relativePath,
    handlerNames: new Set(registry.handlers),
    actions: registry.actions,
    actionIds: new Set(Object.keys(registry.actions))
  };
}

export function validateQuickActionRegistry(registry, registeredWorkflowIds, registeredModeIds, errors) {
  for (const [actionId, entry] of Object.entries(registry.actions)) {
    const ok = entry !== null && typeof entry === "object" && !Array.isArray(entry);

    if (!ok) {
      errors.push(`${registry.relativePath}: action "${actionId}" must map to an object.`);
      continue;
    }

    assert(
      typeof entry.label === "string" && entry.label.length > 0,
      `${registry.relativePath}: action "${actionId}" must declare a non-empty label.`,
      errors
    );
    assert(
      typeof entry.icon === "string" && entry.icon.length > 0,
      `${registry.relativePath}: action "${actionId}" must declare a non-empty icon.`,
      errors
    );
    assert(
      QUICK_ACTION_ARCHETYPES.has(entry.archetype),
      `${registry.relativePath}: action "${actionId}" must declare an archetype (${[...QUICK_ACTION_ARCHETYPES].join(", ")}).`,
      errors
    );
    // `tone` is optional and deliberately narrow: the design allows exactly one
    // differently-coloured slot, so an unrecognised tone is a mistake, not an extension point.
    assert(
      entry.tone === undefined || QUICK_ACTION_TONES.has(entry.tone),
      `${registry.relativePath}: action "${actionId}" declares unknown tone "${entry.tone}" (allowed: ${[...QUICK_ACTION_TONES].join(", ")}).`,
      errors
    );

    // Planned but not built: nothing to resolve. The slot renders labelled and disabled.
    if (entry.target === undefined) {
      continue;
    }

    const target = entry.target;

    if (target === null || typeof target !== "object" || Array.isArray(target)) {
      errors.push(`${registry.relativePath}: action "${actionId}" target must be an object declaring a kind.`);
      continue;
    }

    switch (target.kind) {
      case "handler":
        assert(
          registry.handlerNames.has(target.handler),
          `${registry.relativePath}: action "${actionId}" targets unknown handler "${target.handler}" (handlers list in the same registry).`,
          errors
        );
        break;
      case "workflow":
        assert(
          registeredWorkflowIds.has(target.workflow),
          `${registry.relativePath}: action "${actionId}" targets unknown workflow "${target.workflow}" (config/workflows/*.json).`,
          errors
        );
        break;
      // A report or an input renders in the dashboard — from providers already in dashboard
      // state, or from a form authored in code — so neither has anything in config to resolve.
      // The archetype must agree, though: a target that renders a surface the slot never claimed
      // would be a mislabelled action. A picker shares the Input region, so it takes `input` too.
      case "report":
        assert(
          entry.archetype === "report",
          `${registry.relativePath}: action "${actionId}" has a report target but declares archetype "${entry.archetype}".`,
          errors
        );
        break;
      case "input":
        assert(
          entry.archetype === "input" || entry.archetype === "picker",
          `${registry.relativePath}: action "${actionId}" has an input target but declares archetype "${entry.archetype}".`,
          errors
        );
        break;
      case "layout":
        // A layout action DECLARES its mode rather than having it parsed back out of the id, so
        // both halves are checkable: the mode exists, and it actually has a layout to open.
        assert(
          registeredModeIds.has(target.mode),
          `${registry.relativePath}: action "${actionId}" targets unknown mode "${target.mode}" (config/modes/*.json).`,
          errors
        );
        assert(
          registeredWorkflowIds.has(`open-${target.mode}-layout`),
          `${registry.relativePath}: action "${actionId}" targets mode "${target.mode}", which has no layout to open.`,
          errors
        );
        break;
      default:
        errors.push(
          `${registry.relativePath}: action "${actionId}" target kind must be one of handler, workflow, layout.`
        );
    }
  }
}

function validateModeQuickActions(document, relativePath, registeredActionIds, errors) {
  const slots = Array.isArray(document.quickActions) ? document.quickActions : [];

  for (const actionId of slots) {
    // A null slot is deliberately unconfigured — the renderer omits it (no placeholder tile).
    if (actionId === null) {
      continue;
    }

    assert(
      registeredActionIds.has(actionId),
      `${relativePath}: quickActions entry "${actionId}" must reference a registered quick action (apps/dashboard/src/shell/quickActions.registry.json).`,
      errors
    );
  }
}

function validateMode(document, relativePath, errors, registries) {
  assert(typeof document.id === "string", `${relativePath}: id must be a string.`, errors);
  assert(typeof document.label === "string", `${relativePath}: label must be a string.`, errors);
  assert(
    typeof document.theme === "object" && document.theme !== null && !Array.isArray(document.theme),
    `${relativePath}: theme must be an object.`,
    errors
  );
  assert(
    typeof document.theme?.accentPrimary === "string" && typeof document.theme?.accentSecondary === "string",
    `${relativePath}: theme must define string accentPrimary and accentSecondary tokens.`,
    errors
  );
  assert(Array.isArray(document.quickApps), `${relativePath}: quickApps must be an array.`, errors);
  assert(
    Array.isArray(document.quickApps) && document.quickApps.length >= 0 && document.quickApps.length <= 5,
    `${relativePath}: quickApps must contain between 0 and 5 entries.`,
    errors
  );
  assert(Array.isArray(document.quickActions), `${relativePath}: quickActions must be an array.`, errors);
  assert(
    Array.isArray(document.quickActions) && document.quickActions.length === 8,
    `${relativePath}: quickActions must contain exactly 8 slots (use null for an unconfigured slot).`,
    errors
  );
  assert(
    Array.isArray(document.quickActions) && document.quickActions.every((action) => action === null || typeof action === "string"),
    `${relativePath}: each quick action must be a string id or null.`,
    errors
  );
  const configuredActions = (Array.isArray(document.quickActions) ? document.quickActions : []).filter(
    (action) => typeof action === "string"
  );
  assert(
    new Set(configuredActions).size === configuredActions.length,
    `${relativePath}: quickActions must not repeat a configured action id.`,
    errors
  );
  assert(
    typeof document.widgets === "object" && document.widgets !== null && !Array.isArray(document.widgets),
    `${relativePath}: widgets must be an object.`,
    errors
  );
  assert(
    typeof document.widgets?.left === "string" && typeof document.widgets?.right === "string",
    `${relativePath}: widgets must define string left and right slots.`,
    errors
  );

  // The design spec mandates that Developer, School, and Entertainment each
  // expose their own `open-<modeId>-layout` quick action; Executive's layout
  // action is optional. JSON Schema cannot express this id-derived rule, so it
  // is enforced here.
  if (document.id !== "executive") {
    const layoutAction = `open-${document.id}-layout`;
    assert(
      Array.isArray(document.quickActions) && document.quickActions.includes(layoutAction),
      `${relativePath}: quickActions must include the "${layoutAction}" layout action for non-Executive modes.`,
      errors
    );
  }

  validateModeThemeTokens(document, relativePath, registries.tokenNames, errors);
  validateModeWidgets(document, relativePath, registries.widgetIds, errors);
  validateModeQuickApps(document, relativePath, registries.appIds, errors);
  validateModeQuickActions(document, relativePath, registries.actionIds, errors);
}

function validateWorkflow(document, relativePath, errors, registeredToolIds) {
  assert(typeof document.schemaVersion === "string", `${relativePath}: schemaVersion must be a string.`, errors);
  assert(typeof document.id === "string", `${relativePath}: id must be a string.`, errors);
  assert(
    typeof document.label === "string" && document.label.length > 0,
    `${relativePath}: label must be a non-empty string.`,
    errors
  );
  assert(
    Array.isArray(document.steps) && document.steps.length >= 1,
    `${relativePath}: steps must be a non-empty array.`,
    errors
  );

  const steps = Array.isArray(document.steps) ? document.steps : [];
  const stepIds = [];
  for (const step of steps) {
    const ok = step !== null && typeof step === "object" && !Array.isArray(step);
    assert(ok && typeof step.id === "string", `${relativePath}: every step must have a string id.`, errors);
    assert(ok && typeof step.tool === "string", `${relativePath}: every step must have a string tool.`, errors);
    // A workflow step may only invoke a registered tool. A missing capability is
    // a new tool, never a silently skipped step (the planner mirrors this with a
    // structured error at resolve time).
    if (ok && typeof step.tool === "string") {
      assert(
        registeredToolIds.has(step.tool),
        `${relativePath}: step "${step.id}" references unregistered tool "${step.tool}".`,
        errors
      );
    }
    if (ok && typeof step.id === "string") stepIds.push(step.id);
  }
  assert(
    new Set(stepIds).size === stepIds.length,
    `${relativePath}: step ids must be unique within a workflow.`,
    errors
  );
}

function validateAgent(document, relativePath, errors) {
  assert(typeof document.id === "string", `${relativePath}: id must be a string.`, errors);
  assert(typeof document.label === "string", `${relativePath}: label must be a string.`, errors);
  assert(typeof document.status === "string", `${relativePath}: status must be a string.`, errors);
  assert(typeof document.summary === "string", `${relativePath}: summary must be a string.`, errors);
}

// Model profiles (NIC-243 / ADR-009). The file is OPTIONAL: with no catalog the app runs
// exactly as it does today, because no model is required for the product to work. What is
// checked is the pair the JSON Schema cannot express on its own — a bounded residency needs an
// idle window, and a non-bounded one must not carry a stale number that reads as meaningful.
function validateModelProfiles(document, relativePath, errors) {
  assert(typeof document.schemaVersion === "string", `${relativePath}: schemaVersion must be a string.`, errors);
  assert(Array.isArray(document.modelProfiles), `${relativePath}: modelProfiles must be an array.`, errors);

  const seen = new Set();
  for (const profile of document.modelProfiles ?? []) {
    const id = profile?.id;
    assert(typeof id === "string", `${relativePath}: every profile needs an id.`, errors);
    assert(!seen.has(id), `${relativePath}: profile "${id}" is configured more than once.`, errors);
    seen.add(id);
    assert(typeof profile?.modelId === "string", `${relativePath}: profile "${id}" must name a modelId.`, errors);
    assert(typeof profile?.runtimeId === "string", `${relativePath}: profile "${id}" must name a runtimeId.`, errors);
    assert(
      Number.isInteger(profile?.contextTokens),
      `${relativePath}: profile "${id}" must cap contextTokens — left unset a runtime allocates the model's full advertised window.`,
      errors
    );

    if (profile?.residency === "bounded") {
      assert(
        Number.isInteger(profile?.residencyIdleSeconds),
        `${relativePath}: profile "${id}" is bounded, so it must state residencyIdleSeconds.`,
        errors
      );
    } else {
      assert(
        profile?.residencyIdleSeconds === undefined,
        `${relativePath}: profile "${id}" is ${profile?.residency}, so residencyIdleSeconds does not apply.`,
        errors
      );
    }
  }
}

// Model composers (NIC-250 / NIC-252). Also OPTIONAL: with no catalog no report is
// model-composed. What is checked here is what the JSON Schema cannot state alone — one
// entry per report, and a capability profile that actually resolves. A composer naming a
// profile no catalog defines is configuration that cannot run, and it would fail at the
// moment the user opened the report rather than at validation.
function validateModelComposers(document, relativePath, errors, configuredProfileIds) {
  assert(typeof document.schemaVersion === "string", `${relativePath}: schemaVersion must be a string.`, errors);
  assert(
    typeof document.composerSystemPrompt === "string" && document.composerSystemPrompt.length > 0,
    `${relativePath}: composerSystemPrompt must be a non-empty string.`,
    errors
  );
  assert(Array.isArray(document.composerReports), `${relativePath}: composerReports must be an array.`, errors);

  const seen = new Set();
  for (const composer of document.composerReports ?? []) {
    const id = composer?.composerReportId;
    assert(typeof id === "string", `${relativePath}: every composer needs a composerReportId.`, errors);
    assert(!seen.has(id), `${relativePath}: report "${id}" is composed more than once.`, errors);
    seen.add(id);

    assert(
      typeof composer?.composerInstruction === "string" && composer.composerInstruction.length > 0,
      `${relativePath}: report "${id}" must carry a composerInstruction.`,
      errors
    );
    // Required, not defaulted. A grammar over an under-constrained schema emits valid output
    // forever — measured at 123 blocks and 15,655 tokens before the context wall truncated the
    // document mid-token, which is unparseable rather than merely invalid.
    assert(
      Number.isInteger(composer?.composerMaxOutputTokens),
      `${relativePath}: report "${id}" must cap composerMaxOutputTokens — an uncapped composition can run to the context wall and truncate mid-token.`,
      errors
    );
    assert(
      Number.isInteger(composer?.composerMaxBlocks),
      `${relativePath}: report "${id}" must cap composerMaxBlocks.`,
      errors
    );
    assert(
      configuredProfileIds.size === 0 || configuredProfileIds.has(composer?.modelProfileId),
      `${relativePath}: report "${id}" names modelProfileId "${composer?.modelProfileId}", which no model profile configures.`,
      errors
    );
  }
}

function validateTool(document, relativePath, errors) {
  assert(typeof document.id === "string", `${relativePath}: id must be a string.`, errors);
  assert(typeof document.risk === "string", `${relativePath}: risk must be a string.`, errors);
  assert(typeof document.timeoutMs === "number", `${relativePath}: timeoutMs must be a number.`, errors);
  assert(typeof document.availableInPreMac === "boolean", `${relativePath}: availableInPreMac must be a boolean.`, errors);
}

function validateSimulation(document, relativePath, errors) {
  assert(typeof document.id === "string", `${relativePath}: id must be a string.`, errors);
  assert(typeof document.source === "string", `${relativePath}: source must be a string.`, errors);
  assert(typeof document.modeId === "string", `${relativePath}: modeId must be a string.`, errors);
  assert(typeof document.summary === "string", `${relativePath}: summary must be a string.`, errors);
  assert(Array.isArray(document.steps), `${relativePath}: steps must be an array.`, errors);
  assert(
    Array.isArray(document.steps) && document.steps.every((step) => typeof step === "string"),
    `${relativePath}: every step must be a string.`,
    errors
  );
}

function collectJsonFiles(directoryPath) {
  return fs
    .readdirSync(directoryPath, { withFileTypes: true })
    // statSync follows reparse points; a OneDrive Files-On-Demand placeholder
    // reports isFile()=false from readdir and would be silently skipped.
    .filter((entry) => entry.name.endsWith(".json") && fs.statSync(path.join(directoryPath, entry.name)).isFile())
    .map((entry) => path.join(directoryPath, entry.name));
}

export function validateRepositoryConfig() {
  const { repositoryRoot, configRoot, fixtureRoot } = resolvePaths();
  const errors = [];
  const quickActionRegistry = readQuickActionRegistry(repositoryRoot);
  const registries = {
    tokenNames: readRegisteredModeThemeTokens(repositoryRoot),
    widgetIds: readRegisteredWidgetIds(repositoryRoot),
    appIds: readRegisteredQuickAppIds(repositoryRoot),
    actionIds: quickActionRegistry.actionIds
  };

  const defaultsPath = path.join(configRoot, "defaults", "app.json");
  const modeFiles = collectJsonFiles(path.join(configRoot, "modes"));
  const agentFiles = collectJsonFiles(path.join(configRoot, "agents"));
  const toolFiles = collectJsonFiles(path.join(configRoot, "tools"));
  const descriptorFiles = collectJsonFiles(path.join(configRoot, "tools", "descriptors"));
  // `config/models/` holds two DIFFERENT document families, so it is routed by filename rather
  // than validated wholesale. Before this, every JSON file here was checked as a profile catalog,
  // which meant a second family dropped in beside it would be reported as a malformed catalog —
  // and, worse, an unrecognised filename would be validated as one silently. Both are named now.
  const modelsDir = path.join(configRoot, "models");
  const modelFiles = fs.existsSync(modelsDir) ? collectJsonFiles(modelsDir) : [];
  const modelProfileFiles = modelFiles.filter((filePath) => path.basename(filePath) === "profiles.json");
  const modelComposerFiles = modelFiles.filter((filePath) => path.basename(filePath) === "composer.json");
  for (const filePath of modelFiles) {
    const name = path.basename(filePath);
    assert(
      name === "profiles.json" || name === "composer.json",
      `models/${name}: unrecognised model config file. Expected profiles.json or composer.json.`,
      errors
    );
  }
  const workflowsDir = path.join(configRoot, "workflows");
  const workflowFiles = fs.existsSync(workflowsDir) ? collectJsonFiles(workflowsDir) : [];
  const simulationFiles = collectJsonFiles(path.join(fixtureRoot, "simulations"));

  validateDefaults(readJson(defaultsPath), path.relative(configRoot, defaultsPath), errors);

  for (const filePath of modeFiles) {
    validateMode(readJson(filePath), path.relative(configRoot, filePath), errors, registries);
  }

  for (const filePath of agentFiles) {
    validateAgent(readJson(filePath), path.relative(configRoot, filePath), errors);
  }

  for (const filePath of toolFiles) {
    validateTool(readJson(filePath), path.relative(configRoot, filePath), errors);
  }

  for (const filePath of modelProfileFiles) {
    validateModelProfiles(readJson(filePath), path.relative(configRoot, filePath), errors);
  }

  // The profiles a composer may name. Empty when this machine ships no catalog, in which case the
  // cross-reference is skipped rather than failing every composer — a machine with no model
  // configured is a valid machine, and the composer file is inert there.
  const configuredProfileIds = new Set(
    modelProfileFiles.flatMap((filePath) =>
      (readJson(filePath).modelProfiles ?? []).map((profile) => profile?.id).filter(Boolean)
    )
  );
  for (const filePath of modelComposerFiles) {
    validateModelComposers(
      readJson(filePath), path.relative(configRoot, filePath), errors, configuredProfileIds
    );
  }

  for (const filePath of simulationFiles) {
    validateSimulation(readJson(filePath), path.relative(fixtureRoot, filePath), errors);
  }

  // Workflows resolve their per-step risk from the rich descriptors (the source
  // of truth, all 7 tools), not the stricter-only overlay (only 4 files).
  const registeredToolIds = new Set(descriptorFiles.map((filePath) => readJson(filePath).id));
  const workflowIds = [];
  for (const filePath of workflowFiles) {
    const document = readJson(filePath);
    validateWorkflow(document, path.relative(configRoot, filePath), errors, registeredToolIds);
    if (typeof document.id === "string") workflowIds.push(document.id);
  }
  assert(new Set(workflowIds).size === workflowIds.length, `workflows: workflow ids must be unique across files.`, errors);

  const modeIds = new Set(modeFiles.map((filePath) => readJson(filePath).id));
  const agentIds = new Set(agentFiles.map((filePath) => readJson(filePath).id));
  const defaults = readJson(defaultsPath);

  // Every built quick action must resolve its declared target (ex-NIC-113). Workflow ids come
  // from static files OR from a mode's authored layout (synthesized `open-<mode>-layout`);
  // targetless (planned) entries are unaffected.
  const resolvableWorkflowIds = new Set([...workflowIds, ...readLayoutBackedWorkflowIds(configRoot)]);
  validateQuickActionRegistry(quickActionRegistry, resolvableWorkflowIds, modeIds, errors);

  assert(modeIds.has(defaults.defaultModeId), `defaults/app.json: defaultModeId "${defaults.defaultModeId}" must reference a mode file.`, errors);

  for (const agentId of defaults.enabledAgentIds ?? []) {
    assert(agentIds.has(agentId), `defaults/app.json: enabledAgentId "${agentId}" must reference an agent file.`, errors);
  }

  // enabledToolIds must reference the authoritative descriptors (ADR-003, all 7
  // tools), not the stricter-only overlay subset (config/tools/*.json, 4 files).
  for (const toolId of defaults.enabledToolIds ?? []) {
    assert(registeredToolIds.has(toolId), `defaults/app.json: enabledToolId "${toolId}" must reference a registered tool descriptor.`, errors);
  }

  if (errors.length > 0) {
    fail(`Configuration validation failed:\n- ${errors.join("\n- ")}`);
  }

  return {
    defaultsPath,
    modeCount: modeFiles.length,
    agentCount: agentFiles.length,
    toolCount: toolFiles.length,
    workflowCount: workflowFiles.length,
    simulationCount: simulationFiles.length,
    modelProfileFileCount: modelProfileFiles.length,
    modelComposerFileCount: modelComposerFiles.length
  };
}

export function main() {
  const summary = validateRepositoryConfig();

  console.log(
    `Validated ${summary.modeCount} modes, ${summary.agentCount} agents, ${summary.toolCount} tools, ${summary.workflowCount} workflows, ${summary.simulationCount} simulations, ${summary.modelProfileFileCount} model-profile files, and ${summary.modelComposerFileCount} model-composer files.`
  );
  console.log(`Defaults file: ${summary.defaultsPath}`);
}

if (process.argv[1] && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url) {
  main();
}
