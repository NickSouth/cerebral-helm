// CerebralHelm Canvas Sync — options page (NIC-132).
// Saves the pairing token and sends a hardcoded test scrape through the background worker, so the
// whole extension → local-endpoint → widgets pipe can be verified without touching Canvas.

const TOKEN_KEY = "cerebralhelm_ingest_token";

const tokenInput = document.getElementById("token");
const statusEl = document.getElementById("status");

// Load any saved token into the field.
chrome.storage.local.get(TOKEN_KEY).then((stored) => {
  tokenInput.value = typeof stored[TOKEN_KEY] === "string" ? stored[TOKEN_KEY] : "";
});

document.getElementById("save").addEventListener("click", async () => {
  await chrome.storage.local.set({ [TOKEN_KEY]: tokenInput.value.trim() });
  statusEl.textContent = "Token saved.";
});

document.getElementById("test").addEventListener("click", async () => {
  statusEl.textContent = "Sending test scrape…";
  // A representative payload in the ingest schema CerebralHelm validates (matches CanvasIngestPayload).
  const scrape = {
    sourceUrl: "https://umamherst.instructure.com/",
    courses: [
      { id: "37331", name: "Test Course", code: "COMPSCI 250", percent: 92, letterGrade: "A-" }
    ],
    deadlines: [
      { id: "a1", title: "Problem Set 7", dueAt: "2026-07-30T23:59:00", courseName: "COMPSCI 250" }
    ]
  };

  const result = await chrome.runtime.sendMessage({ type: "canvas-scrape", scrape });
  if (result && result.ok) {
    statusEl.textContent = "✓ CerebralHelm accepted the test scrape (200). Check your School dashboard.";
  } else if (result && result.status === 401) {
    statusEl.textContent = "✗ Rejected (401) — the token doesn't match CerebralHelm. Re-copy it from Settings → Setup → Canvas.";
  } else {
    statusEl.textContent = `✗ ${(result && result.error) || "Failed (status " + ((result && result.status) ?? "?") + ")."}`;
  }
});
