import fs from "node:fs";
import path from "node:path";
import { ensureDirectory, resolveDatabasePath, resolveStateRoot } from "./workspace-roots.mjs";

const databasePath = resolveDatabasePath();
const stateRoot = resolveStateRoot();
const databaseDirectory = path.dirname(databasePath);
const deletedFiles = [];

ensureDirectory(databaseDirectory);

for (const suffix of ["", "-shm", "-wal", "-journal"]) {
  const candidatePath = `${databasePath}${suffix}`;

  if (fs.existsSync(candidatePath)) {
    fs.rmSync(candidatePath, { force: true });
    deletedFiles.push(candidatePath);
  }
}

console.log(`Development state root: ${stateRoot}`);
console.log(`Database path reset target: ${databasePath}`);

if (deletedFiles.length === 0) {
  console.log("No database files existed yet. The dedicated development database directory is ready.");
} else {
  console.log(`Removed ${deletedFiles.length} database file(s).`);
}

console.log("No schema was applied because operational storage has not been implemented yet.");
