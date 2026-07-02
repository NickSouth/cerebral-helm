import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import {
  missingRequiredDocs,
  changelogErrors,
  brokenLinks,
  extractLinkTargets,
  isLocalFileTarget
} from "./validate-docs.mjs";

function withTempDir(run) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "docs-validate-"));
  try {
    return run(dir);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

const VALID_CHANGELOG = `# Changelog

## [Unreleased]

### Added
- something

Config impact: none.
Migration impact: none.
`;

test("a compliant changelog reports no errors", () => {
  assert.deepEqual(changelogErrors(VALID_CHANGELOG), []);
});

test("a changelog entry missing the config-impact line fails", () => {
  const text = VALID_CHANGELOG.replace("Config impact: none.\n", "");
  const errors = changelogErrors(text);
  assert.equal(errors.length, 1);
  assert.match(errors[0], /Config impact/);
});

test("a changelog entry missing the migration-impact line fails", () => {
  const text = VALID_CHANGELOG.replace("Migration impact: none.\n", "");
  const errors = changelogErrors(text);
  assert.equal(errors.length, 1);
  assert.match(errors[0], /Migration impact/);
});

test("a changelog with no version entries fails", () => {
  const errors = changelogErrors("# Changelog\n\nNothing here yet.\n");
  assert.equal(errors.length, 1);
  assert.match(errors[0], /no `## \[version\]` entries/);
});

test("missingRequiredDocs returns only the absent paths", () => {
  withTempDir((dir) => {
    fs.writeFileSync(path.join(dir, "present.md"), "ok");
    const missing = missingRequiredDocs(dir, ["present.md", "absent.md"]);
    assert.deepEqual(missing, ["absent.md"]);
  });
});

test("a dangling relative link is reported, resolving links and externals are not", () => {
  withTempDir((dir) => {
    fs.writeFileSync(path.join(dir, "target.md"), "target");
    const doc = path.join(dir, "index.md");
    fs.writeFileSync(
      doc,
      [
        "[good](target.md)",
        "[bad](does-not-exist.md)",
        "[external](https://example.com)",
        "[anchor](#section)",
        "[mail](mailto:x@example.com)"
      ].join("\n")
    );
    const findings = brokenLinks(dir, [doc]);
    assert.equal(findings.length, 1);
    assert.equal(findings[0].target, "does-not-exist.md");
  });
});

test("extractLinkTargets finds inline and reference-style targets", () => {
  const targets = extractLinkTargets("[a](one.md) and ![img](two.png)\n[ref]: three.md\n");
  assert.deepEqual(targets, ["one.md", "two.png", "three.md"]);
});

test("isLocalFileTarget skips schemes and anchors, accepts relative paths", () => {
  assert.equal(isLocalFileTarget("docs/x.md"), true);
  assert.equal(isLocalFileTarget("../x.md#section"), true);
  assert.equal(isLocalFileTarget("https://example.com"), false);
  assert.equal(isLocalFileTarget("mailto:x@example.com"), false);
  assert.equal(isLocalFileTarget("#in-page"), false);
});
