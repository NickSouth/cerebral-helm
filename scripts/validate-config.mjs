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

// The quick-action wiring manifest is the registry of which quick actions are LIVE (wired to
// a runtime target) versus placeholders. It lives with the UI that dispatches the slots. The
// gate "follows the wiring": an action id absent from the manifest is an allowed placeholder,
// but a *wired* action whose target does not resolve — to a config/workflows/*.json workflow
// id or a declared bridge handler — is a dangling reference and a build failure, the same
// single reference-resolution gate as theme tokens / widgets / quick apps.
export function readQuickActionWiring(repositoryRoot) {
  const manifestPath = path.join(repositoryRoot, "apps", "dashboard", "src", "shell", "quickActions.manifest.json");
  const manifest = readJson(manifestPath);
  const relativePath = path.relative(repositoryRoot, manifestPath);

  if (!Array.isArray(manifest.handlers)) {
    fail(`${relativePath}: handlers must be an array.`);
  }

  if (typeof manifest.wiredActions !== "object" || manifest.wiredActions === null || Array.isArray(manifest.wiredActions)) {
    fail(`${relativePath}: wiredActions must be an object.`);
  }

  return {
    relativePath,
    handlerNames: new Set(manifest.handlers),
    wiredActions: manifest.wiredActions
  };
}

export function validateQuickActionWiring(wiring, registeredWorkflowIds, errors) {
  for (const [actionId, target] of Object.entries(wiring.wiredActions)) {
    const ok = target !== null && typeof target === "object" && !Array.isArray(target);

    if (!ok) {
      errors.push(`${wiring.relativePath}: wired action "${actionId}" must map to an object with a workflow or handler target.`);
      continue;
    }

    const hasWorkflow = typeof target.workflow === "string";
    const hasHandler = typeof target.handler === "string";

    // Exactly one target — a wired action is either workflow-backed or handler-backed, never
    // both (ambiguous) nor neither (dangling).
    if (hasWorkflow === hasHandler) {
      errors.push(`${wiring.relativePath}: wired action "${actionId}" must declare exactly one of workflow or handler.`);
      continue;
    }

    if (hasWorkflow) {
      assert(
        registeredWorkflowIds.has(target.workflow),
        `${wiring.relativePath}: wired action "${actionId}" references unknown workflow "${target.workflow}" (config/workflows/*.json).`,
        errors
      );
    } else {
      assert(
        wiring.handlerNames.has(target.handler),
        `${wiring.relativePath}: wired action "${actionId}" references unknown handler "${target.handler}" (handlers list in the same manifest).`,
        errors
      );
    }
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
  const registries = {
    tokenNames: readRegisteredModeThemeTokens(repositoryRoot),
    widgetIds: readRegisteredWidgetIds(repositoryRoot),
    appIds: readRegisteredQuickAppIds(repositoryRoot)
  };

  const defaultsPath = path.join(configRoot, "defaults", "app.json");
  const modeFiles = collectJsonFiles(path.join(configRoot, "modes"));
  const agentFiles = collectJsonFiles(path.join(configRoot, "agents"));
  const toolFiles = collectJsonFiles(path.join(configRoot, "tools"));
  const descriptorFiles = collectJsonFiles(path.join(configRoot, "tools", "descriptors"));
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

  // Every wired quick action must resolve to a real workflow id or a declared handler
  // (ex-NIC-113). Placeholders (ids not in the manifest) are unaffected.
  validateQuickActionWiring(readQuickActionWiring(repositoryRoot), new Set(workflowIds), errors);

  const modeIds = new Set(modeFiles.map((filePath) => readJson(filePath).id));
  const agentIds = new Set(agentFiles.map((filePath) => readJson(filePath).id));
  const defaults = readJson(defaultsPath);

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
    simulationCount: simulationFiles.length
  };
}

export function main() {
  const summary = validateRepositoryConfig();

  console.log(
    `Validated ${summary.modeCount} modes, ${summary.agentCount} agents, ${summary.toolCount} tools, ${summary.workflowCount} workflows, and ${summary.simulationCount} simulations.`
  );
  console.log(`Defaults file: ${summary.defaultsPath}`);
}

if (process.argv[1] && pathToFileURL(path.resolve(process.argv[1])).href === import.meta.url) {
  main();
}
