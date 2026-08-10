# CerebralHelm Operations Guide

Setup, backup, and recovery for a working installation.

This is written for **future you** — after a machine wipe, a failed migration, or
eighteen months away from this code — and assumes no memory of how any of it was
built. Nothing here requires reading the source.

For the one-time first-Mac bring-up validation, see
[first-mac-bootstrap-checklist.md](first-mac-bootstrap-checklist.md); that is a
historical record of a single validation pass, not a living runbook.

## 1. Where your data lives

CerebralHelm keeps **everything durable outside the application bundle**, so
replacing the app can never touch your data. The production state root is:

```
~/Library/Application Support/CerebralHelm
```

Never guess the path — ask the installation:

```bash
cerebral doctor
```

> **`cerebral` is not on your `PATH` by default.** It is a developer and recovery
> CLI built from this repository. Build it with `swift build --product cerebral`
> and run it as `./.build/debug/cerebral` from the repository root, or symlink it
> somewhere on your `PATH`. Every `cerebral` command in this guide assumes that.
> It defaults to the `development` environment — set `CEREBRAL_ENV=production` and
> `CEREBRAL_STATE_ROOT` to work against your real data.

It prints the resolved environment and every root, and exits non-zero if storage
needs recovery. Confirm it says `Environment: production`. If it says
`development`, you are looking at the in-repo `.local/development` root, not your
real data.

| What | Path under the state root | Rebuildable? |
|---|---|---|
| Markdown knowledge base | `knowledge/` | **No — this is the irreplaceable one** |
| Operational database | `database/cerebral.sqlite` | No |
| Per-mode config overrides | `overrides/` | No |
| Last-known-good config | `active-config.json` | Regenerated on next load |
| Config version / rollback metadata | `settings-metadata.json` | Regenerated on next load |
| Active mode / context | `active-mode.json`, `active-context.json` | Falls back to the default mode |
| Mode session history | `sessions/mode-sessions.ndjson` | No, but non-critical |
| Automatic backups | `backups/` | — |
| Event log | `events/events.ndjson` | No, but non-critical |
| Favicon cache | `cache/favicons/` | Yes — safe to delete |

**To back up everything by hand, copy the whole state root.** That is the complete
picture apart from the two exceptions below.

### Exception 1 — secrets are in the Keychain, not the state root

API keys and OAuth tokens live in the login Keychain under the service
**`local.cerebralhelm.secrets`**. They are *not* in the state root and *not* in
any backup. After a wipe you re-enter them — see §7.

### Exception 2 — three preferences are in `UserDefaults`

These live in `~/Library/Preferences/local.cerebralhelm.CerebralHelm.plist` and
are deliberately outside the state root, so a restore will **not** bring them back:

- `palette.summonPreset` — the command-palette hotkey
- `sidebar.edgeRevealEnabled`, `sidebar.edgeDwellPreset` — edge-sidebar behaviour

They take seconds to set again in Settings. Knowing this in advance stops a
restore looking broken when your hotkey is back to the default.

## 2. Install from source

There is no download, no installer, and no update channel. CerebralHelm is built
from this repository and copied into place.

```bash
xcodebuild -project apps/mac/CerebralHelm.xcodeproj -scheme CerebralHelm -configuration Release build
```

Then copy the built `CerebralHelm.app` into `/Applications`.

### Signing — do not skip this

The app must be signed with a **stable Apple Development identity**, not ad-hoc.
An ad-hoc signature is cdhash-based, so macOS treats every rebuild as a different
application and **every permission grant below dies on each rebuild**.

A free Apple ID is sufficient. In Xcode: Settings → Accounts → add your Apple ID,
then open `apps/mac/CerebralHelm.xcodeproj`, select the **CerebralHelm** target →
Signing & Capabilities → **All** → set Team to your Personal Team. Confirm:

```bash
codesign -d -r- /Applications/CerebralHelm.app
```

The designated requirement must reference `anchor apple generic` and a
certificate. If you see `cdhash`, signing did not take.

**Certificates expire annually.** When yours is renewed the certificate CN
changes, which changes the designated requirement — so expect to re-grant the
permissions in §3 once per renewal. That is expected, not a fault.

## 3. Permissions

Granted in System Settings → Privacy & Security. Each one buys a specific
capability, and nothing else breaks when it is missing:

| Permission | Needed for | Without it |
|---|---|---|
| **Accessibility** | Window arrangement, geometry capture, per-mode window layouts | Windows are not moved or restored; the rest works |
| **Automation** | Per-mode Chrome windows by profile | Chrome opens without profile/window separation |
| **Location** | The weather widget | Weather shows unavailable |

If window management silently stops working after a rebuild, the Accessibility
grant is the first thing to check — see the signing note in §2.

## 4. Routine backup

Automatic backups happen **before any schema migration**, into
`backups/<timestamp>/`. A backup that cannot be written or verified blocks the
migration rather than proceeding. The newest five are kept.

To take one yourself at any time:

```bash
cerebral backup
```

It copies the database with a checksum, includes config and overrides, records a
SHA-256 manifest of every note, and verifies the result before reporting success.

Automatic backups only cover *migrations*. They are not a substitute for a real
backup of `~/Library/Application Support/CerebralHelm` — use Time Machine or copy
the state root somewhere else as well.

## 5. Restore

Each backup is a directory under `backups/<timestamp>/` containing:

- `cerebral.sqlite` — the database as it was
- `active-config.json`, `settings-metadata.json` — configuration
- `overrides/` — your per-mode overrides
- `manifest.json` — checksums, including one per knowledge file

**Restore is a deliberate manual copy. There is no automatic repair, and no
`cerebral restore` command** — recovery never happens without you asking for it,
so nothing can silently overwrite good data with old data.

1. **Quit CerebralHelm.** Restoring underneath a running app will not end well.
2. Pick the backup: `ls ~/Library/Application\ Support/CerebralHelm/backups/`
3. Copy the current state aside first, so a bad restore is reversible:
   ```bash
   cp -R ~/Library/Application\ Support/CerebralHelm ~/Desktop/CerebralHelm-before-restore
   ```
4. Copy `cerebral.sqlite`, `active-config.json`, `settings-metadata.json`, and
   `overrides/` from the backup directory back into the state root.
5. Launch, then run `cerebral doctor` and confirm it reports healthy.

**Your notes are not in the backup, by design.** The Markdown files in
`knowledge/` are the source of truth and are never overwritten by a restore — the
manifest records their checksums so you can tell whether any changed. If you need
the notes themselves back, they come from your own filesystem backup.

The search index is derived and rebuilds from the Markdown, so it does not need
restoring. If search looks wrong afterwards, rebuild it:

```bash
cerebral knowledge rebuild
```

## 6. When something is wrong

```bash
cerebral doctor
```

Reports the environment, every root, and whether storage is healthy. Exit code 2
means recovery is needed; it names the failing store and what to do. It never
repairs anything on its own — a corrupt database is reported and left untouched,
never deleted or rebuilt behind your back.

## 7. Re-provisioning integrations after a wipe

Keys are entered in **Settings → Setup** inside the app. They are written straight
to the Keychain and never land in config or a log. This is the tedious part of a
rebuild, so the full list is here:

| Integration | Keychain reference | Where to get it |
|---|---|---|
| TMDB (releases) | `tmdb_api_key` | themoviedb.org → account → API |
| Finnhub (stocks) | `finnhub_api_key` | finnhub.io → dashboard |
| NewsData (news) | `newsdata_api_key` | newsdata.io → dashboard |
| GitHub (repos) | `github_api_token` | github.com → Settings → Developer settings → personal access token |
| Linear | `linear_api_token` | linear.app → Settings → API |
| Spotify | `spotify_client_id`, `spotify_oauth` | developer.spotify.com — needs the redirect URI registered |
| Google / Gmail | `google_client_id`, `google_client_secret`, `google_oauth` | Google Cloud console → OAuth client |
| Canvas | `canvas_ingest_token` | Generated by the Canvas browser extension |

Weather (Open-Meteo) and scores (ESPN) need no key.

Spotify and Google are OAuth rather than plain keys: you provide the client
credentials once, then complete a sign-in flow in the app.

## 8. Clean shutdown

Quit normally. There is no shutdown sequence to observe — every durable write is
atomic or transactional, so terminating at any moment leaves either the old state
or the new one, never a half-written file.

If the app is killed mid-migration, the next launch either re-runs the migration
from the pre-migration backup state or finds it already complete. It cannot land
half-applied.
