import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { resolveRepositoryRoot } from "./workspace-roots.mjs";

// Documentation and compatibility gate (NIC-70 / NFR-10).
//
// - Required decision docs must exist (AC-10): a manifest of ADRs, specs, and
//   compatibility metadata; a missing/renamed path fails CI.
// - Relative markdown links across the authored docs must resolve — a dangling file
//   reference is a build failure. External (http/mailto) links and in-page anchors
//   are not fetched or resolved.
// - Every CHANGELOG entry must declare config and migration impact (AC-12).
//
// The functions are exported and side-effect-free so `validate-docs.test.mjs` can
// exercise each failure mode against synthetic inputs.

// Doc roots whose markdown links are checked. Scoped to authored docs; node_modules
// and build output are never walked.
const LINK_ROOTS = ["README.md", "CHANGELOG.md", "CLAUDE.md", "docs", ".agent/spec", "wiki"];

export function missingRequiredDocs(repositoryRoot, requiredDocs) {
  return requiredDocs.filter((relativePath) => !fs.existsSync(path.join(repositoryRoot, relativePath)));
}

/**
 * CHANGELOG convention: every `## [version]` section must declare both a
 * `Config impact:` and a `Migration impact:` line (AC-12). Pure string → errors.
 */
export function changelogErrors(text) {
  const errors = [];
  const lines = text.split(/\r?\n/);
  const headingIndexes = [];
  lines.forEach((line, index) => {
    if (/^## \[/.test(line)) {
      headingIndexes.push(index);
    }
  });

  if (headingIndexes.length === 0) {
    errors.push("CHANGELOG.md has no `## [version]` entries.");
    return errors;
  }

  headingIndexes.forEach((start, position) => {
    const end = position + 1 < headingIndexes.length ? headingIndexes[position + 1] : lines.length;
    const heading = lines[start].trim();
    const body = lines.slice(start + 1, end);
    if (!body.some((line) => /^config impact:/i.test(line.trim()))) {
      errors.push(`CHANGELOG entry "${heading}" is missing a "Config impact:" line.`);
    }
    if (!body.some((line) => /^migration impact:/i.test(line.trim()))) {
      errors.push(`CHANGELOG entry "${heading}" is missing a "Migration impact:" line.`);
    }
  });

  return errors;
}

function collectMarkdownFiles(repositoryRoot, roots) {
  const files = [];
  const walk = (absolutePath) => {
    const stats = fs.statSync(absolutePath);
    if (stats.isDirectory()) {
      for (const entry of fs.readdirSync(absolutePath)) {
        walk(path.join(absolutePath, entry));
      }
    } else if (stats.isFile() && absolutePath.toLowerCase().endsWith(".md")) {
      files.push(absolutePath);
    }
  };
  for (const root of roots) {
    const absolute = path.join(repositoryRoot, root);
    if (fs.existsSync(absolute)) {
      walk(absolute);
    }
  }
  return files;
}

/** Extracts inline `](target)` and reference-style `[label]: target` link targets. */
export function extractLinkTargets(markdown) {
  const targets = [];
  const inline = /\]\(\s*([^)]+?)\s*\)/g;
  const reference = /^\s*\[[^\]]+\]:\s+(\S+)/gm;
  let match;
  while ((match = inline.exec(markdown)) !== null) {
    targets.push(match[1]);
  }
  while ((match = reference.exec(markdown)) !== null) {
    targets.push(match[1]);
  }
  return targets;
}

/** True when a link target is a local file reference that should resolve on disk. */
export function isLocalFileTarget(rawTarget) {
  let target = rawTarget.trim();
  if (target.startsWith("<") && target.endsWith(">")) {
    target = target.slice(1, -1);
  }
  target = target.split(/\s+/)[0]; // drop any `"title"` suffix
  target = target.split("#")[0]; // drop in-page anchor
  if (target === "") {
    return false; // pure in-page anchor
  }
  if (/^[a-z][a-z0-9+.-]*:/i.test(target) || target.startsWith("//")) {
    return false; // external scheme or protocol-relative
  }
  return true;
}

function resolvedTargetPath(rawTarget) {
  let target = rawTarget.trim();
  if (target.startsWith("<") && target.endsWith(">")) {
    target = target.slice(1, -1);
  }
  target = target.split(/\s+/)[0].split("#")[0];
  try {
    return decodeURIComponent(target);
  } catch {
    return target;
  }
}

export function brokenLinks(repositoryRoot, files) {
  const findings = [];
  for (const file of files) {
    const markdown = fs.readFileSync(file, "utf8");
    for (const rawTarget of extractLinkTargets(markdown)) {
      if (!isLocalFileTarget(rawTarget)) {
        continue;
      }
      const resolved = path.resolve(path.dirname(file), resolvedTargetPath(rawTarget));
      if (!fs.existsSync(resolved)) {
        findings.push({ file: path.relative(repositoryRoot, file), target: rawTarget.trim() });
      }
    }
  }
  return findings;
}

export function validateDocs(repositoryRoot = resolveRepositoryRoot()) {
  const errors = [];

  const manifestPath = path.join(repositoryRoot, "docs", "required-docs.json");
  if (!fs.existsSync(manifestPath)) {
    throw new Error("docs/required-docs.json is missing.");
  }
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  if (!Array.isArray(manifest.requiredDocs) || manifest.requiredDocs.length === 0) {
    throw new Error("docs/required-docs.json: requiredDocs must be a non-empty array.");
  }

  for (const missing of missingRequiredDocs(repositoryRoot, manifest.requiredDocs)) {
    errors.push(`Required document is missing: ${missing}`);
  }

  const changelogPath = path.join(repositoryRoot, "CHANGELOG.md");
  if (fs.existsSync(changelogPath)) {
    errors.push(...changelogErrors(fs.readFileSync(changelogPath, "utf8")));
  }

  const markdownFiles = collectMarkdownFiles(repositoryRoot, LINK_ROOTS);
  for (const finding of brokenLinks(repositoryRoot, markdownFiles)) {
    errors.push(`Broken relative link in ${finding.file}: ${finding.target}`);
  }

  return { errors, requiredCount: manifest.requiredDocs.length, markdownCount: markdownFiles.length };
}

export function main() {
  const { errors, requiredCount, markdownCount } = validateDocs();
  if (errors.length > 0) {
    throw new Error(`Documentation validation failed:\n- ${errors.join("\n- ")}`);
  }
  console.log(
    `Docs OK: ${requiredCount} required documents present; links resolve across ${markdownCount} markdown files; CHANGELOG entries declare config + migration impact.`
  );
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main();
}
