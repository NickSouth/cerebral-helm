import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const repositoryRoot = path.resolve(scriptDirectory, "..");
const localRoot = path.join(repositoryRoot, ".local");
const developmentRoot = path.join(localRoot, "development");
const fixtureRoot = path.join(repositoryRoot, "fixtures");
const configRoot = path.join(repositoryRoot, "config");
const defaultDatabasePath = path.join(developmentRoot, "database", "cerebral.sqlite");
const defaultEventLogPath = path.join(developmentRoot, "events", "events.ndjson");
const defaultSimulationOutputRoot = path.join(developmentRoot, "simulations");

function fail(message) {
  throw new Error(message);
}

function normalizePath(targetPath) {
  return path.normalize(targetPath);
}

function ensureWithinRepository(targetPath, label) {
  const normalizedRepositoryRoot = normalizePath(repositoryRoot + path.sep);
  const normalizedTargetPath = normalizePath(targetPath);

  if (
    normalizedTargetPath !== normalizePath(repositoryRoot) &&
    !normalizedTargetPath.startsWith(normalizedRepositoryRoot)
  ) {
    fail(`${label} must stay inside the repository workspace. Received "${targetPath}".`);
  }
}

function ensureNonProductionPath(targetPath, label) {
  const lowerTargetPath = targetPath.toLowerCase();
  const blockedSegments = ["production", "personal-prod", "personal_production"];

  if (blockedSegments.some((segment) => lowerTargetPath.includes(segment))) {
    fail(`${label} must not point at a personal or production-looking path. Received "${targetPath}".`);
  }
}

export function resolveRepositoryRoot() {
  return repositoryRoot;
}

export function resolvePaths() {
  return {
    repositoryRoot,
    configRoot,
    fixtureRoot,
    localRoot,
    developmentRoot,
    defaultDatabasePath,
    defaultEventLogPath,
    defaultSimulationOutputRoot
  };
}

export function resolveStateRoot() {
  const configuredRoot = process.env.CEREBRAL_STATE_ROOT;
  const resolvedRoot = configuredRoot
    ? path.resolve(repositoryRoot, configuredRoot)
    : developmentRoot;

  ensureWithinRepository(resolvedRoot, "State root");
  ensureNonProductionPath(resolvedRoot, "State root");

  return resolvedRoot;
}

export function resolveDatabasePath() {
  const configuredPath = process.env.CEREBRAL_DATABASE_PATH;
  const resolvedPath = configuredPath
    ? path.resolve(repositoryRoot, configuredPath)
    : path.join(resolveStateRoot(), "database", "cerebral.sqlite");

  ensureWithinRepository(resolvedPath, "Database path");
  ensureNonProductionPath(resolvedPath, "Database path");

  return resolvedPath;
}

export function resolveEventLogPath() {
  const configuredPath = process.env.CEREBRAL_EVENT_LOG_PATH;
  const resolvedPath = configuredPath
    ? path.resolve(repositoryRoot, configuredPath)
    : path.join(resolveStateRoot(), "events", "events.ndjson");

  ensureWithinRepository(resolvedPath, "Event log path");
  ensureNonProductionPath(resolvedPath, "Event log path");

  return resolvedPath;
}

export function resolveSimulationOutputRoot() {
  const configuredRoot = process.env.CEREBRAL_SIMULATION_OUTPUT_ROOT;
  const resolvedRoot = configuredRoot
    ? path.resolve(repositoryRoot, configuredRoot)
    : path.join(resolveStateRoot(), "simulations");

  ensureWithinRepository(resolvedRoot, "Simulation output root");
  ensureNonProductionPath(resolvedRoot, "Simulation output root");

  return resolvedRoot;
}

export function ensureDirectory(targetPath) {
  fs.mkdirSync(targetPath, { recursive: true });
}

export function describeRoots() {
  return {
    repositoryRoot,
    configRoot,
    fixtureRoot,
    stateRoot: resolveStateRoot(),
    databasePath: resolveDatabasePath(),
    eventLogPath: resolveEventLogPath(),
    simulationOutputRoot: resolveSimulationOutputRoot()
  };
}
