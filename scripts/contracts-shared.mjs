import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { InputData, JSONSchemaInput, quicktype } from "quicktype-core";
import { resolveRepositoryRoot } from "./workspace-roots.mjs";

export const repositoryRoot = resolveRepositoryRoot();
export const contractsRoot = path.join(repositoryRoot, "packages", "contracts");
export const schemasRoot = path.join(contractsRoot, "schemas");
export const fixturesRoot = path.join(contractsRoot, "fixtures");
export const typescriptOutputPath = path.join(contractsRoot, "generated", "typescript", "contracts.ts");
export const swiftOutputPath = path.join(contractsRoot, "Sources", "CerebralContracts", "GeneratedContracts.swift");

export function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

export function writeText(filePath, content) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, content.endsWith("\n") ? content : `${content}\n`);
}

export function collectJsonFiles(directoryPath) {
  return fs
    .readdirSync(directoryPath, { withFileTypes: true })
    .flatMap((entry) => {
      const entryPath = path.join(directoryPath, entry.name);
      if (entry.isDirectory()) {
        return collectJsonFiles(entryPath);
      }

      return entry.isFile() && entry.name.endsWith(".json") ? [entryPath] : [];
    })
    .sort((left, right) => left.localeCompare(right));
}

export function collectSchemaFiles() {
  return collectJsonFiles(schemasRoot);
}

export function contractNameForSchema(filePath) {
  const relativePath = path.relative(schemasRoot, filePath);
  const withoutExtension = relativePath.replace(/\.schema\.json$/, "");

  return withoutExtension
    .split(/[\\/.-]+/)
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join("");
}

function lookupJsonPointer(document, pointer) {
  if (!pointer || pointer === "#") {
    return document;
  }

  const parts = pointer
    .replace(/^#\//, "")
    .split("/")
    .filter(Boolean)
    .map((part) => part.replaceAll("~1", "/").replaceAll("~0", "~"));

  return parts.reduce((current, part) => current?.[part], document);
}

function stripSchemaIdentity(document) {
  if (!document || typeof document !== "object" || Array.isArray(document)) {
    return document;
  }

  const { $schema, $id, title, ...rest } = document;
  return rest;
}

function dereferenceSchemaNode(node, currentFilePath, schemaFilesById, visitedRefs = new Set()) {
  if (Array.isArray(node)) {
    return node.map((item) => dereferenceSchemaNode(item, currentFilePath, schemaFilesById, visitedRefs));
  }

  if (!node || typeof node !== "object") {
    return node;
  }

  if (typeof node.$ref === "string") {
    const ref = node.$ref;
    const [refPath, fragment = ""] = ref.split("#");
    let refFilePath = currentFilePath;

    if (refPath) {
      refFilePath = refPath.startsWith("https://")
        ? schemaFilesById.get(refPath)
        : path.resolve(path.dirname(currentFilePath), refPath);
    }

    const visitedKey = `${refFilePath}#${fragment}`;
    if (visitedRefs.has(visitedKey)) {
      return {};
    }

    visitedRefs.add(visitedKey);
    const refDocument = readJson(refFilePath);
    const refTarget = lookupJsonPointer(refDocument, fragment ? `#${fragment}` : "#");
    const dereferenced = dereferenceSchemaNode(stripSchemaIdentity(refTarget), refFilePath, schemaFilesById, visitedRefs);
    visitedRefs.delete(visitedKey);

    return dereferenced;
  }

  return Object.fromEntries(
    Object.entries(node).map(([key, value]) => [key, dereferenceSchemaNode(value, currentFilePath, schemaFilesById, visitedRefs)])
  );
}

function simplifySchemaForQuicktype(node) {
  if (Array.isArray(node)) {
    return node.map((item) => simplifySchemaForQuicktype(item));
  }

  if (!node || typeof node !== "object") {
    return node;
  }

  const entries = Object.entries(node)
    .filter(([key]) => !["if", "then", "else", "allOf"].includes(key))
    .filter(([key, value]) => key !== "const" || typeof value === "string")
    .map(([key, value]) => [key, simplifySchemaForQuicktype(value)]);

  return Object.fromEntries(entries);
}

function schemaFilesById() {
  return new Map(collectSchemaFiles().map((filePath) => [readJson(filePath).$id, filePath]));
}

export function bundledSchemaForQuicktype(filePath) {
  const schema = readJson(filePath);
  const bundled = simplifySchemaForQuicktype(dereferenceSchemaNode(schema, filePath, schemaFilesById()));

  return {
    ...bundled,
    $schema: schema.$schema,
    title: schema.title
  };
}

export async function renderContracts(language) {
  const schemaInput = new JSONSchemaInput(undefined);

  for (const filePath of collectSchemaFiles()) {
    await schemaInput.addSource({
      name: contractNameForSchema(filePath),
      schema: JSON.stringify(bundledSchemaForQuicktype(filePath))
    });
  }

  const inputData = new InputData();
  inputData.addInput(schemaInput);

  const rendererOptions =
    language === "swift"
      ? {
          "just-types": false,
          "struct-or-class": "struct",
          "access-level": "public"
        }
      : {
          "just-types": true
        };

  const result = await quicktype({
    inputData,
    lang: language,
    alphabetizeProperties: true,
    rendererOptions,
    leadingComments: [
      "Generated by scripts/generate-contracts.mjs.",
      "Do not edit by hand; edit packages/contracts/schemas instead."
    ]
  });

  const source = `${result.lines.join("\n")}\n`;

  if (language === "swift") {
    return normalizeGeneratedSwift(source);
  }

  return source;
}

function normalizeGeneratedSwift(source) {
  return source
    .replace(
      "    public var hashValue: Int {\n            return 0\n    }",
      "    public func hash(into hasher: inout Hasher) {}"
    )
    .replace("class JSONCodingKey: CodingKey {", "final class JSONCodingKey: CodingKey {");
}

export async function generateContracts(outputRoot = contractsRoot) {
  const generatedTypescriptPath = path.join(outputRoot, "generated", "typescript", "contracts.ts");
  const generatedSwiftPath = path.join(outputRoot, "Sources", "CerebralContracts", "GeneratedContracts.swift");

  const [typescript, swift] = await Promise.all([renderContracts("typescript"), renderContracts("swift")]);

  writeText(generatedTypescriptPath, typescript);
  writeText(generatedSwiftPath, swift);

  return {
    generatedTypescriptPath,
    generatedSwiftPath
  };
}

export function makeTemporaryContractOutputRoot() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "cerebral-contracts-"));
}

export function invokedDirectly(importMetaUrl) {
  return process.argv[1] && path.resolve(process.argv[1]) === path.resolve(fileURLToPath(importMetaUrl));
}
