import { spawnSync } from "node:child_process";
import path from "node:path";

function fail(message) {
  throw new Error(message);
}

function resolveCommand(command) {
  if (process.platform !== "win32") {
    return command;
  }

  const extension = path.extname(command);

  if (extension) {
    return command;
  }

  if (command === "corepack") {
    return "corepack.cmd";
  }

  return command;
}

function useShellForCommand(command) {
  return process.platform === "win32" && command.endsWith(".cmd");
}

function parseSemver(rawVersion) {
  const match = rawVersion.trim().match(/\bv?(\d+)\.(\d+)\.(\d+)/);

  if (!match) {
    fail(`Unable to parse semantic version from "${rawVersion}".`);
  }

  return {
    major: Number(match[1]),
    minor: Number(match[2]),
    patch: Number(match[3]),
    raw: rawVersion.trim()
  };
}

function compareSemver(left, right) {
  if (left.major !== right.major) {
    return left.major - right.major;
  }

  if (left.minor !== right.minor) {
    return left.minor - right.minor;
  }

  return left.patch - right.patch;
}

export function assertNodeVersion(minimumVersion) {
  const current = parseSemver(process.version);
  const minimum = parseSemver(minimumVersion);

  if (compareSemver(current, minimum) < 0) {
    fail(`Node ${minimum.raw} or newer is required. Found ${current.raw}.`);
  }

  return current.raw;
}

export function runCommand(command, args, options = {}) {
  const resolvedCommand = resolveCommand(command);
  const result = spawnSync(resolvedCommand, args, {
    stdio: "inherit",
    shell: useShellForCommand(resolvedCommand),
    ...options
  });

  if (result.error) {
    fail(`Failed to start "${command}": ${result.error.message}`);
  }

  if (result.status !== 0) {
    fail(`"${command} ${args.join(" ")}" exited with code ${result.status}.`);
  }
}

export function captureCommand(command, args, options = {}) {
  const resolvedCommand = resolveCommand(command);
  const result = spawnSync(resolvedCommand, args, {
    encoding: "utf8",
    shell: useShellForCommand(resolvedCommand),
    ...options
  });

  if (result.error) {
    fail(`Failed to start "${command}": ${result.error.message}`);
  }

  if (result.status !== 0) {
    const stderr = result.stderr?.trim();
    const suffix = stderr ? ` ${stderr}` : "";
    fail(`"${command} ${args.join(" ")}" exited with code ${result.status}.${suffix}`);
  }

  return result.stdout.trim();
}

export function assertBinaryVersion(command, args, minimumVersion) {
  const rawVersion = captureCommand(command, args);
  const current = parseSemver(rawVersion);
  const minimum = parseSemver(minimumVersion);

  if (compareSemver(current, minimum) < 0) {
    fail(`${command} ${minimum.raw} or newer is required. Found ${current.raw}.`);
  }

  return current.raw;
}
