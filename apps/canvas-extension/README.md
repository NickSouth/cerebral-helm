# CerebralHelm Canvas Sync (Chrome extension)

Feeds the **School** dashboard's Deadlines and Courses widgets (NIC-132). It reads your Canvas
dashboard and posts the result to CerebralHelm's local ingest endpoint
(`http://127.0.0.1:8899/canvas/ingest`), authenticated with a pairing token. **Scraped data never
leaves your Mac** — it goes only to the local app over loopback.

This is a plain MV3 extension (no build step). It is intentionally **not** part of the Swift/TS app
build; load it unpacked in Chrome.

## Files

- `manifest.json` — MV3 manifest. Host permissions: your Canvas host + the loopback endpoint.
- `background.js` — service worker. Owns the endpoint + token; adds the bearer token and POSTs
  scrapes. The token/endpoint live only here, never in the page.
- `content.js` — runs on Canvas pages. Reads the new dashboard's courses/grades and upcoming
  assignments (via stable `data-testid`s) and posts on load, plus a periodic refresh while the tab
  stays open. It scrapes **only** when the dashboard widgets are present, so a deep course page never
  wipes the stored scrape.
- `options.html` / `options.js` — paste the pairing token and send a test scrape.

## Install (load unpacked)

1. Open `chrome://extensions` and turn on **Developer mode** (top right).
2. Click **Load unpacked** and select this `apps/canvas-extension` folder.
3. Open the extension's **Options** (Details → Extension options, or the puzzle-piece menu).

## Pair + test (Increment 7a)

1. Launch CerebralHelm, then open **Settings → Setup → Canvas** and copy the token.
2. Paste it into the extension options and click **Save token**.
3. Click **Send test scrape**. You should see "accepted (200)", and the School dashboard's Courses
   and Deadlines widgets should fill with the test data.
   - **401** means the token doesn't match — re-copy it from Settings.
   - "Couldn't reach CerebralHelm" means the app isn't running.

## Use it for real

Once loaded and paired, just open your Canvas dashboard — the extension scrapes it and the School
widgets fill in. It re-scrapes on each dashboard visit and periodically while the tab stays open.

**One selector to confirm in the fall:** the courses/grades extraction and the "no upcoming work"
empty state are confirmed against a live dashboard, but the *populated* upcoming-assignment row shape
couldn't be observed off-season, so `scrapeDeadlines()` reads it defensively (assignment links + a
nested `<time>` for the due date, excluding submitted/completed). When you have a real course load,
check that deadlines appear and tune the selectors in `scrapeDeadlines()` if needed — nothing else
changes, because the payload shape CerebralHelm consumes is frozen.

**Not yet:** pulling the *full* dashboard while you're deep in a course page (it currently scrapes
when you're on the dashboard). That needs a managed background dashboard tab — deferred pending a
decision on carrying a pinned Canvas tab.

## If a different Canvas host

The manifest is scoped to `umamherst.instructure.com`. For a different institution, change both the
`host_permissions` and `content_scripts.matches` entries to that Canvas domain.
