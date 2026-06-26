import fs from "node:fs";
import { resolveEventLogPath } from "./workspace-roots.mjs";

function fail(message) {
  throw new Error(message);
}

const requestedLines = Number(process.argv[2] ?? "20");
const lineCount = Number.isInteger(requestedLines) && requestedLines > 0 ? requestedLines : 20;
const eventLogPath = resolveEventLogPath();

if (!fs.existsSync(eventLogPath)) {
  fail(`No development event log exists yet at ${eventLogPath}. The event stream will arrive with the runtime implementation.`);
}

const lines = fs
  .readFileSync(eventLogPath, "utf8")
  .split(/\r?\n/)
  .filter((line) => line.length > 0);

for (const line of lines.slice(-lineCount)) {
  console.log(line);
}

console.log(`Displayed ${Math.min(lineCount, lines.length)} event line(s) from ${eventLogPath}.`);
