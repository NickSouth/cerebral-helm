// CerebralHelm Canvas Sync — background service worker (NIC-132).
//
// Owns the local ingest endpoint and the pairing token, and POSTs scrapes to CerebralHelm. The
// token and endpoint live only here (never in the content script), so a page can't read them. The
// content script (and the options "Send test scrape" button) hand a scrape here via a message; this
// worker adds the bearer token and posts it to the loopback endpoint.

// The loopback endpoint CerebralHelm listens on (AppBridgeRuntime, port 8899). Loopback-only, so
// nothing off-machine is involved.
const INGEST_ENDPOINT = "http://127.0.0.1:8899/canvas/ingest";
// Where the paired token is stored (set in the options page).
const TOKEN_KEY = "cerebralhelm_ingest_token";
// The ingest payload schema this extension speaks; CerebralHelm rejects any other version.
const SCHEMA_VERSION = 1;

async function getToken() {
  const stored = await chrome.storage.local.get(TOKEN_KEY);
  const token = stored[TOKEN_KEY];
  return typeof token === "string" && token.length > 0 ? token : null;
}

/**
 * POST a scrape to the local endpoint. `scrape` is `{ sourceUrl?, courses, deadlines }`; the schema
 * version and scrape time are added here. Returns `{ ok, status, error? }` — never throws.
 */
async function postScrape(scrape) {
  const token = await getToken();
  if (!token) {
    return { ok: false, status: 0, error: "No token yet — paste your CerebralHelm token in the extension options." };
  }

  const payload = {
    schemaVersion: SCHEMA_VERSION,
    scrapedAt: new Date().toISOString(),
    sourceUrl: scrape && scrape.sourceUrl ? scrape.sourceUrl : null,
    courses: (scrape && scrape.courses) || [],
    deadlines: (scrape && scrape.deadlines) || []
  };

  try {
    const response = await fetch(INGEST_ENDPOINT, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`
      },
      body: JSON.stringify(payload)
    });
    return { ok: response.ok, status: response.status };
  } catch (error) {
    // The app isn't running, or the port is closed — surface an honest, non-technical message.
    return { ok: false, status: 0, error: "Couldn't reach CerebralHelm — is the app running?" };
  }
}

// A scrape arrives from the options page (a test payload) or, in Increment 7b, the content script.
chrome.runtime.onMessage.addListener((message, _sender, sendResponse) => {
  if (message && message.type === "canvas-scrape") {
    postScrape(message.scrape).then(sendResponse);
    return true; // keep the channel open for the async response
  }
  return false;
});
